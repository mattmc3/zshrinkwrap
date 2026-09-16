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

- **Ghostty** with its shell integration loaded clears marked prompts itself,
  so zshrinkwrap stays out of the way.
- **VS Code and Apple Terminal** use the split strategy. At each prompt,
  zshrinkwrap prints every prompt line but the last as ordinary output, so zle
  only draws the input line. On the first resize the input line collapses to a
  small symbol with the command stashed and the right prompt removed, so
  nothing zle draws while resizing can wrap. Once resizing settles, the upper
  lines are measured up from the cursor row at the final width, cleared, and
  printed again with the full prompt and command.
- **Other terminals** use the older estimate strategy: guess how many rows the
  rewrapped display occupies and climb that far before zsh redraws. It is not
  verified on any terminal yet.

Known limits of the split strategy: a very fast first resize step can still
leave one stale row when zsh's output lags behind the terminal, and upper
prompt lines are not refreshed by async theme updates or `reset-prompt` until
the next prompt.

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
zstyle ':zshrinkwrap:resize' strategy estimate
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

The `strategy` style picks how a resize is handled. By default it depends on
the terminal:

- `none`: leave the prompt alone. Used in Ghostty when its shell integration
  is loaded.
- `split`: print upper prompt lines outside zle and redraw once resizing
  settles. Used in VS Code and Apple Terminal. It always collapses both
  prompts during a resize, ignoring `shrink-lprompt` and `shrink-rprompt`.
- `estimate`: estimate how far reflow moved the prompt. Used everywhere else.

## Test

Install [Bats](https://bats-core.readthedocs.io/), then run:

```sh
bats test/plugin.bats
```

## License

[MIT](LICENSE)
