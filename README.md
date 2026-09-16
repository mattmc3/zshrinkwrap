# zshrinkwrap

<img src="assets/zshrinkwrap.svg" alt="zshrinkwrap" height="100" align="right">

> Shrink-wrap your Zsh prompt during terminal resize.

> [!WARNING]
> This project is still experimental. It might never be perfect, but it should
> work far better than the Zsh defaults.

Many terminals reflow visible text before Zsh handles `SIGWINCH`. Zsh can then
redraw its prompt from the wrong screen position, leaving duplicated or damaged
prompt lines. zshrinkwrap picks a strategy for the terminal it runs in.

## Demo

Resizing Apple Terminal with a powerlevel10k prompt, without zshrinkwrap:

![Resizing without zshrinkwrap leaves copies of the prompt](https://github.com/mattmc3/zshrinkwrap/blob/assets/resizing-artifacts.gif?raw=true)

The same terminal and prompt with zshrinkwrap:

![Resizing with zshrinkwrap keeps a single clean prompt](https://github.com/mattmc3/zshrinkwrap/blob/assets/zshrinkwrap-demo.gif?raw=true)

## How it works

When you resize a terminal, it rewraps the text already on screen before Zsh
learns the new size. If your prompt takes more than one row, that rewrap
changes how far the top of the prompt is from the cursor, so Zsh redraws from
the wrong place.

zshrinkwrap prints all but the last line of your prompt as regular output, so
Zsh only has to redraw the line you type on. When a resize starts, that line
shrinks to a short symbol and your command is set aside. When the resize stops,
the full prompt is drawn again and your command comes back.

Some terminals already handle this themselves. Ghostty and kitty clear and
redraw the prompt on resize when their shell integration is loaded, so
zshrinkwrap stays out of the way there.

powerlevel10k is supported directly, so its transient prompt and async segments
keep working. Other themes that update a multi-line prompt in place may show
old upper lines until the next prompt.

Limits:

- A very fast resize can still leave a stray row when the terminal gets ahead
  of Zsh.
- Terminals that cut off long lines instead of rewrapping them (eg: plain
  xterm) should use the `none` strategy.

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
