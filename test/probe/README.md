# Resize probes

Small manual scripts for finding out how each terminal behaves on resize.
Their results decide which strategy zshrinkwrap uses per terminal. Run them
directly in the terminal under test, not inside tmux, since tmux does its own
reflow.

Terminals to cover: VS Code, iTerm2, WezTerm, Ghostty, Apple Terminal.

## Long command

Copy/paste this:

```sh
echo The quick brown fox jumps over the lazy dog. Now is the time for all good men to come to the aid of their country.
```

## decsc.zsh

Does the saved cursor (DECSC/DECRC) move along with reflowed text? If it does,
the prompt origin can be saved at precmd and found again after any resize.

```sh
zsh test/probe/decsc.zsh
```

Shrink the window, press Enter, widen it, press Enter. Report whether `[1]`
and `[2]` landed on the `A> anchor` line.

Report the column too: a correct restore puts `[1]` at the start of the line.
Run `zsh test/probe/decsc.zsh short` to keep the anchor line itself from
wrapping, which separates reflow above the anchor from reflow of the anchor.

## anchor.zsh

Can a saved-cursor anchor keep the prompt clean through a resize?

```sh
zsh -f
source test/probe/anchor.zsh twoline auto   # layout: oneline|twoline
```

Modes:

- `auto`: fix the anchor and redraw on every resize event.
- `collapse`: fix the anchor on the first resize event, show a short prompt
  while resizing, and redraw the full prompt once resizing settles.
- `manual`: do nothing on resize. Press Ctrl-G to redraw from the anchor.

Run a few commands so there is history above the prompt, then resize back and
forth, both slowly and quickly. Report whether the prompt ends clean, whether
stale prompt lines remain, and whether any history was eaten. Try with a long
command typed but not run, too.

## split.zsh

Does printing the upper prompt lines outside zle make resize race-free? zle
only draws the last prompt line. While resizing, that line collapses to a short
prompt with the command stashed, so it never wraps. Once resizing settles, the
upper lines are cleared and reprinted at the new width, measured up from the
input line.

```sh
zsh -f
source test/probe/split.zsh tworight cursor   # layout: oneline|twoline|tworight
```

The anchor argument picks how the input line is found once resizing settles:

- `cursor`: the cursor row. Works whether or not the terminal rewraps the
  cursor's own line.
- `decsc`: a cursor saved at precmd. Only safe where the terminal leaves the
  cursor's own line alone on resize (VS Code), but immune to zsh output lag.

Resize slowly and quickly, with no command, a short command, and a command long
enough to wrap before you start. Report as for `anchor.zsh`.

## marks.zsh

With OSC 133 (or VS Code's OSC 633) prompt marks, does the terminal clear the
prompt on resize and leave zsh to redraw it?

```sh
zsh -f
source test/probe/marks.zsh 133 twoline   # marks: 133|633|none
```

Start a fresh `zsh -f` for each run. Resize back and forth several times at
the prompt without pressing anything, with and without a long command typed.
Report `clean` if a single prompt remains, or `staircase` if stale prompt
fragments pile up above it. Run the same resize pattern with `none` as the
baseline: the marks only matter if `none` makes a staircase and `133` does not.

## Reporting

Paste the `terminal:` and `TERM=` lines each probe prints, then one line per
probe, eg:

```
terminal: ghostty 1.3.0
TERM=xterm-ghostty zsh=5.9 size=120x40
decsc: [1] on anchor, [2] on anchor
anchor twoline: clean, no history lost
marks 133 twoline: clean / none twoline: staircase
```
