# Resize probes

Small manual scripts for finding out how a terminal behaves on resize. Their
results decide which strategy zshrinkwrap should use there. Run them directly
in the terminal under test, not inside tmux, since tmux does its own reflow.
See ARCHITECTURE.md for how to add a terminal.

## Long command

An example long command to paste and leave unrun while resizing:

```sh
echo The quick brown fox jumps over the lazy dog. Now is the time for all good men to come to the aid of their country.
```

## decsc.zsh

Does the saved cursor (DECSC/DECRC) move along with reflowed text?

```sh
zsh test/probe/decsc.zsh long   # or short, cursor
```

Shrink the window, press Enter, widen it, press Enter. A saved cursor that
follows reflow puts `[1]` at the start of the `A> anchor` line and `[2]` four
columns in; note the row and column where each lands.

- `long`: the anchor line fills the width, so it wraps when shrinking.
- `short`: the anchor line never wraps, which separates reflow above the anchor
  from reflow of the anchor line itself.
- `cursor`: the cursor stays on the long anchor line, like a right prompt.

## split.zsh

Does printing the upper prompt lines outside zle keep the prompt clean through
a resize? zle only draws the last prompt line. While resizing, that line collapses to a short
prompt with the command stashed, so it never wraps. Once resizing settles, the
upper lines are cleared and reprinted at the new width, measured up from the
input line.

```sh
zsh -f
source test/probe/split.zsh tworight cursor   # layout: oneline|twoline|tworight
```

The anchor argument picks how the input line is found once resizing settles:

- `cursor`: the cursor row. This is what the plugin uses.
- `decsc`: a cursor saved at precmd. Kept for comparison; it left stale rows
  in real VS Code and fails where the terminal rewraps the cursor's own line.

Run a few commands first so there is history above the prompt, then resize
slowly and quickly, with no command, a short command, and a command long
enough to wrap before you start. Check that the prompt ends clean, that no
stale prompt lines remain, and that no history was erased.

## marks.zsh

With OSC 133 (or VS Code's OSC 633) prompt marks, does the terminal clear the
prompt on resize and leave zsh to redraw it?

```sh
zsh -f
source test/probe/marks.zsh 133 twoline   # marks: 133|633|none
```

Start a fresh `zsh -f` for each run. Resize back and forth several times at
the prompt without pressing anything, with and without a long command typed.
The result is clean if a single prompt remains, or a staircase if stale prompt
fragments pile up above it. Run the same resize pattern with `none` as the
baseline: the marks only matter if `none` makes a staircase and `133` does not.
