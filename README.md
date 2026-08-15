# zshrinkwrap

<img src="assets/zshrinkwrap.svg" alt="zshrinkwrap" height="100" align="right">

> Shrink-wrap your Zsh prompt during terminal resize.

> [!WARNING]
> This project is still experimental. Use with caution for now.

Many terminals reflow visible text before Zsh handles `SIGWINCH`. Zsh can then
redraw its prompt from the wrong screen position, leaving duplicated or damaged
prompt lines. zshrinkwrap mitigates this by temporarily:

- replacing the left prompt with a small symbol;
- removing the right prompt; and
- enabling single-line editing so long command lines scroll instead of wrap.

After resizing settles, zshrinkwrap restores the original prompts and editor
mode. This reduces artifacts but cannot prevent terminal reflow that happens
before Zsh receives `SIGWINCH`.

## How cleanup works

When the prompt line is longer than the new terminal width, the terminal
rewraps it across several physical rows before Zsh receives `SIGWINCH`.
Clearing only the cursor row leaves fragments of the old prompt above it.

zshrinkwrap instead estimates how many rows the rewrapped display occupies,
using the visible prompt width, the cursor offset in the edit buffer, and the
new terminal width. It moves the cursor to the top of that region, clears to
the end of the screen, and redraws.

This assumes the terminal rewraps soft-wrapped lines to the new width, which
Ghostty, Apple Terminal, WezTerm, iTerm2, kitty, VTE terminals, and VS Code
all do. Terminals that truncate instead of rewrap (plain xterm) may see the
clear region land slightly off. Prompts that occupy exactly the full terminal
width can also throw the estimate off by one row.

## Requirements

- Zsh
- `sleep`

## Install

Clone the repository, then source the plugin after your prompt theme:

```zsh
source /path/to/zshrinkwrap/zshrinkwrap.plugin.zsh
```

## Configure

Styles are read at resize time, so set them before or after sourcing the
plugin:

```zsh
zstyle ':zshrinkwrap:resize' symbol '%F{magenta}❯%f '
zstyle ':zshrinkwrap:resize' restore-delay 0.20
zstyle ':zshrinkwrap:resize' shrink-lprompt false
zstyle ':zshrinkwrap:resize' shrink-rprompt true
zstyle ':zshrinkwrap:resize' reflow true
```

The `symbol` style supports Zsh prompt escapes, including `%F{color}` and
`%f`. It defaults to `%F{magenta}%#%f `. The `restore-delay` style defaults to
`0.20` seconds. Setting a style to an empty value falls back to its default.

The `shrink-lprompt` and `shrink-rprompt` styles control which prompts shrink
during resize. `shrink-lprompt` defaults to `false`; `shrink-rprompt` defaults
to `true`.

The `reflow` style compensates for the terminal rewrapping the prompt at the
new width. It defaults to `true`. Set it to `false` in terminals that do not
reflow existing lines on resize, or when the correction itself misplaces the
prompt.

## Test

Install [Bats](https://bats-core.readthedocs.io/), then run:

```sh
bats test/plugin.bats
```

## License

[MIT](LICENSE)
