# Architecture

This document explains what zshrinkwrap does, why it is built the way it is,
what has been tried, and what is still open. Read it before changing resize
handling. The terminal behavior it depends on is subtle, and most obvious fixes
have already been tried and failed.

## The problem

When a Zsh prompt is on screen and the terminal window is resized, many
terminals leave a "staircase" of duplicated or broken prompt lines, and can
even erase lines of scrollback. It is most visible with right prompts,
multi-line prompts, and long command lines.
[powerlevel10k's troubleshooting guide][p10k-mess] describes it in detail:

1. The terminal **reflows** (rewraps) existing text to the new width.
2. Only then does it send `SIGWINCH` to the shell.
3. Zsh redraws the prompt by climbing up from the cursor by the number of rows
   it *believes* sit between the prompt's top and the cursor. That count was
   computed for the old width. Reflow changed the real count, so zsh redraws
   from the wrong row: too low leaves stale copies above, too high erases
   history.

The project started with the idea of detecting a resize, "shrinkwrapping" the
prompt (hiding the right prompt, and maybe the left) while it happens, and
restoring it afterward.

## Hard constraints

These shape every design decision.

- **There is no resize-start event.** Reflow happens before `SIGWINCH`, so every
  fix runs after the damage is done. In-band resize reports (DEC mode 2048) and
  polling `COLUMNS` have the same problem.
- **Zsh redraws before `TRAPWINCH` runs.** On `SIGWINCH`, zle's own refresh
  climbs its believed row offset, clears with `ED`, and redraws at the new
  width. The trap sees the result, not the pre-redraw state.
- **Terminals differ.** Some reflow and some truncate. They also differ on
  whether they rewrap the cursor's own line and how they move a saved cursor
  (DECSC). No single cursor-math model fits all of them.
- **Output lags behind resizes.** Resize events arrive faster than the
  terminal processes zsh's output. Anything computed from `COLUMNS` can be
  applied after the terminal has already moved to a different width. Designs
  that correct on every `SIGWINCH` break down under this race.
- **No trading everyday UX for resize.** Hiding the right prompt whenever the
  user is idle was considered and rejected. The screen may look mangled
  *during* a resize, but it must be clean when the resize ends.

## Design overview

zshrinkwrap chooses a **strategy per terminal** in `_zshrinkwrap_strategy`,
based on `$TERM_PROGRAM`. Users can override it:

```zsh
zstyle ':zshrinkwrap:resize' strategy none|split|estimate
```

| Terminal | Strategy | Status |
|---|---|---|
| Ghostty, shell integration loaded | `none` | Probes verified; plugin not yet exercised in a real shell |
| VS Code | `split` | Verified with the real plugin, starship, and zsh-patina |
| Apple Terminal | `split` | Verified with the split probe; plugin not yet exercised in a real shell |
| Ghostty without integration, iTerm2, WezTerm, others | `estimate` | Legacy, not verified anywhere |

### `none`

Do nothing on resize. Ghostty clears prompts marked with OSC 133 on resize and
lets the shell redraw them. Ghostty's zsh integration adds those marks, so
when it is loaded (`_ghostty_precmd` or `_ghostty_deferred_init` exists) the
plugin stays out of the way.

### `split`

The main mechanism. Its states:

**At rest (precmd).** `_zshrinkwrap_split_precmd`:

- Evaluates `PROMPT`, running `prompt_subst` expansion if that option is set.
- Prints every line except the last as ordinary output, and records each
  line's display width.
- Sets `PROMPT` to only the last line, so zle draws a single line. With
  `prompt_subst`, `PROMPT` becomes `${_zshrinkwrap_split_line}`, so the
  already-evaluated text is not evaluated again.
- Wraps `RPROMPT` in `%{\e[?7l%}...%{\e[?7h%}`, which turns autowrap off while
  the right prompt is written (see below).
- Leaves single-line prompts alone, apart from the `RPROMPT` wrap.

Printed upper lines reflow like any other history, and zle never climbs into
them.

**First `SIGWINCH` of a burst.** In `TRAPWINCH`, via `_zshrinkwrap_adjust`:

- Saves `PROMPT`, `RPROMPT`, `CURSOR`, and `region_highlight`.
- Stashes the command with `zle push-line`.
- Sets `PROMPT` to the `symbol` style and clears `RPROMPT`.

The input line is now short enough that no zle redraw during the resize can
wrap it, so its position no longer depends on the width.

**Later `SIGWINCH`es.** Only push the restore deadline back.

**Settle.** Runs after `restore-delay` seconds (default 0.20) with no
`SIGWINCH`. A `sleep` subprocess fd is watched with `zle -F -w`, and the
handler `_zshrinkwrap_timer_ready` is a widget. `_zshrinkwrap_split_redraw`:

1. The collapsed input line is on the cursor row. Nothing else depends on
   where the terminal moved things.
2. Restore the prompts, `zle get-line`, restore `CURSOR` and
   `region_highlight`.
3. Move up by the rows the recorded upper lines take at the *final*
   `COLUMNS`, `\r\e[0J`, reprint the upper lines at the new width, and
   `zle reset-prompt`.

**preexec.** `_zshrinkwrap_split_preexec` restores the theme's original
`PROMPT` and `RPROMPT`, so commands and other hooks never see the split
versions. If a theme changes either prompt between prompts, its value wins at
the next precmd.

Why each piece exists:

- **Anchor on the cursor row, not a saved cursor.** A DECSC anchor set at
  precmd was tried. Apple Terminal rewraps the cursor's line, so the saved
  cursor slips a row on shrink. Real VS Code also left stale rows, even though
  the harness favored DECSC. The cursor row is correct in both terminals once
  the input line is collapsed.
- **Autowrap off around `RPROMPT`.** Zsh reaches the right prompt with `CUF`,
  which stops at the screen edge. It then writes the text and moves back with
  `CUB`. If the terminal has already shrunk past zsh's `COLUMNS`, that text
  autowraps and the cursor drops a row. That left one stale prompt copy per
  drag burst in VS Code. With DECAWM off, the text overwrites the last column
  instead.
- **Timer handler as a widget (`zle -F -w`).** A plain fd handler does not
  have live zle state. Setting `region_highlight` from it changed an ordinary
  shell variable, and syntax highlighting (zsh-patina) vanished after the
  command was restored.
- **Collapse instead of `singlelinezle`.** Single-line editing still draws the
  command at zsh's idea of the width, which can wrap when output lags.

### `estimate` (legacy)

- On each `SIGWINCH`, compute how many rows the prompt and command take at the
  old and new widths.
- Move the cursor up by the difference, so zle's end-of-trap refresh starts
  from the true top.
- Optionally hide the prompts (`shrink-lprompt`, `shrink-rprompt`), and restore
  them on a timer.
- `reflow false` disables the cursor-up move.

It assumes the terminal reflows, does not account for commands whose wrapped
rows became separate lines, and is exposed to the output-lag race. It remains
the default only because the terminals that use it have not been tested with
`split`.

## Code map

Everything lives in `zshrinkwrap.plugin.zsh`.

| Function | Role |
|---|---|
| `_zshrinkwrap_style` | Read a zstyle, treating empty values as unset |
| `_zshrinkwrap_strategy` | Pick `none`, `split`, or `estimate` |
| `TRAPWINCH` | Chain any previous trap, then adjust and start the settle timer |
| `_zshrinkwrap_adjust` | `estimate` climb; save and collapse prompts, stash the command |
| `_zshrinkwrap_start_timer`, `_zshrinkwrap_timer_ready`, `_zshrinkwrap_cancel_timer` | Debounced settle timer on a `sleep` fd |
| `_zshrinkwrap_restore` | Restore prompts, command, cursor, highlighting (also a precmd hook) |
| `_zshrinkwrap_rows_above` | Rows between the prompt top and the cursor at a given width |
| `_zshrinkwrap_split_precmd`, `_zshrinkwrap_split_print` | Print upper prompt lines, hand zle the last line, wrap `RPROMPT` |
| `_zshrinkwrap_split_preexec` | Give the theme its prompts back before a command |
| `_zshrinkwrap_split_redraw` | Settle-time climb, clear, and reprint for `split` |
| `_zshrinkwrap_display_width` | Width of a line with escape sequences removed |

Hooks, in registration order:

- precmd: `_zshrinkwrap_restore`, then `_zshrinkwrap_split_precmd`
- preexec: `_zshrinkwrap_split_preexec`

Sourcing the plugin again restores state and any previous `TRAPWINCH` before
redefining everything.

## Terminal behavior reference

| Behavior | Ghostty 1.3 | VS Code 1.138 (xterm.js) | Apple Terminal 488 |
|---|---|---|---|
| Reflows text on resize | yes | yes | yes |
| Clears OSC 133 marked prompt on resize | yes | no (133 or 633) | not tested |
| Rewraps the cursor's own line | not tested | no, cut off (`reflowCursorLine` off on macOS) | yes |
| Saved cursor follows reflow of lines above | yes | yes | yes |
| Saved cursor when its own line wraps | correct | slips to the continuation row | slips on shrink, correct after widen |

More xterm.js details, from [`Buffer.ts`][xterm-buffer]:

- **Saved cursor on reflow.** The saved row shifts by the rows added or
  removed across the whole buffer, not only above it. The cursor's own wrapped
  group is skipped unless `reflowCursorLine` is on, and VS Code only turns it
  on for ConPTY ([`terminalInstance.ts`][vscode-reflow]).
- **Erasing a row.** Erasing from column 0 clears the row's wrap flag. Zsh
  crosses a wrap in typed input with `\r\e[K`, so the rows of a wrapped command
  become separate lines that reflow independently.

tmux does not move the saved cursor with reflow. It is a poor stand-in for real
terminals.

## What was tried

In roughly chronological order.

| Approach | Outcome |
|---|---|
| Hide `RPROMPT`, clear the cursor row, `reset-prompt` | Staircase with long commands; fragments left above |
| `estimate`: climb `(promptwidth + CURSOR) / COLUMNS`, clear, redraw | Ate history: moved twice, once by the plugin and once by zle's own climb |
| `estimate`: climb only the delta between old and new row counts | Best of the estimate line. Clean in the tmux sim except one stale pair when a step hit a redraw whose wrapped rows had become separate lines |
| OSC 133 prompt marks | Ghostty clears marked prompts: adopted as `none`. VS Code ignores both 133 and 633 |
| DECSC anchor at precmd, redraw from it on every `SIGWINCH` | Fixed some VS Code cases. Wrong when the anchor's own line wraps, and parked one row too low |
| DECSC anchor with a correction for wrapped prompt lines, per `SIGWINCH` (`anchor.zsh auto`) | Clean on slow resizes. Under output lag the correction lands at the wrong width and eats history (harness: 4/10 at 15ms) |
| Correct once, then collapse the prompt until settle (`anchor.zsh collapse`) | Better (7/10 at 15ms). Still left a stale partial line in real VS Code |
| Split upper lines + `singlelinezle` + DECSC anchor | Clean in VS Code for two-line prompts. Apple Terminal failed with a right prompt, because its saved cursor slips when the cursor line wraps |
| Split + collapse + cursor-row anchor | Clean in real VS Code and Apple Terminal: **adopted as `split`** |
| Split + collapse + DECSC anchor | Harness preferred it; real VS Code left stale rows. Rejected |
| Hide the right prompt whenever idle | Rejected for UX |
| [romkatv's zsh patch][romkatv-patch] (sc/rc around prompt) | Would need a rebuilt zsh; only helps terminals that move the saved cursor. Not pursued |

Corrections to earlier beliefs:

- An early note said zsh parks the cursor one row below its drawing before
  `TRAPWINCH`, so the trap needed an extra row. Raw byte captures later showed
  that zle's redraw inside the trap climbs only its believed cursor row. The
  extra row made redraws land one row low.
- The harness measured DECSC as more robust than the cursor anchor. Real VS
  Code disagreed. When the harness and a real terminal disagree, trust the
  real terminal.

## Known limitations

- **First-`SIGWINCH` race.** Zsh's own redraw on the first `SIGWINCH` happens
  before the plugin can collapse anything. A command long enough to wrap at
  that moment can leave a stale row or climb too far, most likely when
  resuming a drag after a pause longer than `restore-delay`.
- **Heavy output lag.** At about 40ms of simulated lag, the settle redraw can
  arrive after the next resize has started.
- **Themes.** Upper prompt lines are static until the next prompt: async theme
  updates and `reset-prompt` from other plugins do not refresh them.
  Transient prompts and hook ordering have only been checked with starship in
  VS Code.
- **Top of screen.** If the upper prompt lines scroll above the visible area
  during a resize, the cursor-up at settle stops at the top and can leave rows
  behind.
- **`estimate` terminals** are unverified.

## Testing

### Unit tests

```sh
bats test/plugin.bats
```

- Tests run `zsh -fc` with a stubbed `zle` function.
- `setup` clears `TERM_PROGRAM`, so running the suite inside a terminal cannot
  change the strategy.
- Follow red/green: write a failing test first.

### Manual probes (`test/probe/`)

Standalone scripts that isolate one terminal behavior each. Run them directly
in the terminal under test, not inside tmux, and from `zsh -f`, which also
keeps terminal shell integration out of the way.

| Probe | Question |
|---|---|
| `decsc.zsh long\|short\|cursor` | Does the saved cursor follow reflow above it, of its own line, and on the cursor line? |
| `marks.zsh none\|133\|633 <layout>` | Does the terminal clear a marked prompt on resize? |
| `anchor.zsh <layout> auto\|collapse\|manual` | DECSC anchor redraw variants |
| `split.zsh <layout> cursor\|decsc` | The split design, with either anchor |

Layouts come from `common.zsh`:

- `oneline`: a short prompt with a right prompt.
- `twoline`: the p10k repro, a full-width first line.
- `tworight`: `twoline` plus a right prompt.

### Adding a terminal (eg: iTerm2, WezTerm)

1. **Check whether marks are enough.** From `zsh -f`, run
   `source test/probe/marks.zsh none twoline`, then `... 133 twoline`. If
   `none` leaves a staircase and `133` is clean, the terminal clears marked
   prompts. Use `none` when its shell integration is loaded, and find a
   reliable way to detect that.
2. **Otherwise, try split.** From `zsh -f`, run
   `source test/probe/split.zsh tworight cursor`. Resize with pauses at an
   empty prompt, with a short command, and with a long command. If it stays
   clean, add the terminal to the `split` case in `_zshrinkwrap_strategy`.
3. **Confirm with the real plugin** and a real theme before calling it done.
4. **Explain failures** with `decsc.zsh` if needed.

### Headless xterm.js harness (not in the repo)

Useful for byte-level captures and regression runs.

- **Packages:** `@xterm/headless` and `node-pty`. Make the prebuilt
  `spawn-helper` executable.
- **Setup:** spawn `zsh -f -i`, then on each resize call `term.resize` before
  `pty.resize`.
- **Simulating lag:** optionally delay pty output before writing it to the
  terminal.
- **Output:** dump buffer lines with their wrap flags and colored cells.
- **Scenarios:** random resize sequences with optional pauses, across layouts
  and latencies.

It does not fully model VS Code timing. Use it to find bugs, not to choose
between designs.

Earlier work also used a pyte-based sim (a non-reflowing terminal, where zsh
needs no help) and a tmux sim with `pipe-pane` for raw bytes.

## Lessons

- **Settle arguments with bytes, not theories.** Capture what zsh wrote for
  one resize step, then look at the screen. Most wrong turns were settled this
  way.
- **Test in the real terminal before adopting a design.** Probes cost little.
  Plugin rewrites based on a theory cost a lot.
- **Do nothing that depends on width while a resize is in flight.** Collapse,
  wait for the resize to settle, then act once.

## References

- [powerlevel10k: horrific mess when resizing terminal window][p10k-mess]
- [romkatv's zsh `fix-winchanged` patch][romkatv-patch] and the
  [zsh-workers discussion][zsh-workers]
- [kitty shell integration][kitty-si], the origin of prompt clearing on resize
- [Ghostty shell integration docs][ghostty-si] and its
  [zsh integration script][ghostty-zsh]
- [xterm.js `Buffer.ts`][xterm-buffer]: reflow and saved cursor handling
- [VS Code `terminalInstance.ts`][vscode-reflow]: `reflowCursorLine` setting
- [zsh-patina][patina]: syntax highlighter driven by `line-pre-redraw`
- Zsh manual: `zle -F` (with `-w`), `zle push-line`/`get-line`,
  `region_highlight`, `add-zle-hook-widget`

[p10k-mess]: https://github.com/romkatv/powerlevel10k#horrific-mess-when-resizing-terminal-window
[romkatv-patch]: https://github.com/romkatv/zsh/tree/fix-winchanged
[zsh-workers]: https://www.zsh.org/mla/workers//2019/msg00561.html
[kitty-si]: https://sw.kovidgoyal.net/kitty/shell-integration/
[ghostty-si]: https://ghostty.org/docs/features/shell-integration
[ghostty-zsh]: https://github.com/ghostty-org/ghostty/blob/main/src/shell-integration/zsh/ghostty-integration
[xterm-buffer]: https://github.com/xtermjs/xterm.js/blob/master/src/common/buffer/Buffer.ts
[vscode-reflow]: https://github.com/microsoft/vscode/blob/main/src/vs/workbench/contrib/terminal/browser/terminalInstance.ts
[patina]: https://github.com/michel-kraemer/zsh-patina
