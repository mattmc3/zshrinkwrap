# zshrinkwrap

<img src="assets/zshrinkwrap.svg" alt="zshrinkwrap" height="100" align="right">

> Shrink-wrap your Zsh prompt during terminal resize.

> [!WARNING]
> This project is still experimental. It might never be perfect, but it should
> work far better than the Zsh defaults.

Many terminals reflow visible text before Zsh handles `SIGWINCH`. Zsh can then
redraw its prompt from the wrong screen position, leaving duplicated or damaged
prompt lines. zshrinkwrap picks a strategy for the terminal it runs in.

## How cleanup works

The damage comes from rows between the top of the prompt and the cursor
changing height when the terminal rewraps them. Zsh climbs back to the top
using the old height and redraws from the wrong row.

- **Ghostty and kitty** with their shell integration loaded clear marked
  prompts themselves, so zshrinkwrap stays out of the way.
- **Every other terminal** uses the split strategy. At each prompt,
  zshrinkwrap prints every prompt line but the last as ordinary output, so zle
  only draws the input line. On the first resize the input line collapses to a
  small symbol with the command stashed and the right prompt removed, so
  nothing zle draws while resizing can wrap. Once resizing settles, the upper
  lines are measured up from the cursor row at the final width, cleared, and
  printed again with the full prompt and command.

Known limits of the split strategy: a very fast first resize step can still
leave one stale row when zsh's output lags behind the terminal, and upper
prompt lines are not refreshed by async theme updates or `reset-prompt` until
the next prompt. It assumes the terminal rewraps lines on resize; in terminals
that truncate them instead (eg: plain xterm), set the strategy to `none`.

## Tested terminals

Tested on macOS with Zsh 5.9:

- **Ghostty** and **kitty** with shell integration: left to the terminal.
- **VS Code**, **Apple Terminal**, and **WezTerm**: split strategy, clean in
  manual resize testing, including with a long command typed.
- **iTerm2** (with or without its shell integration): split strategy, clean at
  an empty prompt.
- **tmux**: split strategy, clean at an empty prompt. Resizing with a long
  command already typed can leave a stale row, because tmux notifies the shell
  of resizes late.

Other terminals, including Linux terminals, get the split strategy but have
not been tested yet.

## Requirements

- Zsh 5.1 or newer
- `sleep`

## Install

Clone the repository, then source the plugin after your prompt theme:

```zsh
source /path/to/zshrinkwrap/zshrinkwrap.plugin.zsh
```

## Configure

Styles use the context `:zshrinkwrap:resize:<terminal>`, where `<terminal>` is
`$TERM_PROGRAM`, or `$TERM` when that is unset. Set a style for every terminal
with `*`, and override it for one terminal by name; the most specific pattern
wins:

```zsh
# All terminals
zstyle ':zshrinkwrap:resize:*' symbol '%F{magenta}❯%f '
zstyle ':zshrinkwrap:resize:*' stashed-symbol '%F{magenta}❯%f %F{8}…%f'
zstyle ':zshrinkwrap:resize:*' restore-delay 0.20

# One terminal
zstyle ':zshrinkwrap:resize:tmux' restore-delay 0.40
zstyle ':zshrinkwrap:resize:Apple_Terminal' strategy none
```

To see the terminal name zshrinkwrap uses, run `echo ${TERM_PROGRAM:-$TERM}`.
Common names are `vscode`, `Apple_Terminal`, `iTerm.app`, `WezTerm`, `ghostty`,
`tmux`, and `xterm-kitty`. Styles are read each time they are used, so set
them before or after sourcing the plugin.

The `symbol` style is the short prompt shown while resizing. Keep it to one
short line. It supports Zsh prompt escapes, including `%F{color}` and `%f`, and
defaults to `%F{magenta}%#%f `. When a command is typed, it is stashed while
resizing and `stashed-symbol` is shown instead, defaulting to `%F{magenta}%#%f
%F{8}…%f`. If your terminal draws ambiguous-width characters as double width,
use `...` instead of `…`. The `restore-delay` style is how long resizing must
pause before the full prompt is redrawn, and defaults to `0.20` seconds. Setting
a style to an empty value falls back to its default.

The `strategy` style picks how a resize is handled:

- `split`: print upper prompt lines outside zle and redraw once resizing
  settles. The default.
- `none`: leave the prompt alone. The default in Ghostty and kitty when their
  shell integration is loaded.

## Test

Install [Bats](https://bats-core.readthedocs.io/), then run:

```sh
bats test/plugin.bats
```

## License

[MIT](LICENSE)
