# zshrinkwrap

Shrink-wrap your Zsh prompt during terminal resize.

Many terminals reflow visible text before Zsh handles `SIGWINCH`. Zsh can then
redraw its prompt from the wrong screen position, leaving duplicated or damaged
prompt lines. zshrinkwrap mitigates this by temporarily:

- replacing the left prompt with a small symbol;
- removing the right prompt; and
- enabling single-line editing so long command lines scroll instead of wrap.

After resizing settles, zshrinkwrap restores the original prompts and editor
mode. This reduces artifacts but cannot prevent terminal reflow that happens
before Zsh receives `SIGWINCH`.

## Requirements

- Zsh
- `sleep`

## Install

Clone the repository, then source the plugin after your prompt theme:

```zsh
source /path/to/zshrinkwrap/zshrinkwrap.plugin.zsh
```

## Configure

Set either option before sourcing the plugin:

```zsh
ZSHINKWRAP_SYMBOL='%F{magenta}❯%f '
ZSHINKWRAP_RESTORE_DELAY=0.20
```

`ZSHINKWRAP_SYMBOL` supports Zsh prompt escapes, including `%F{color}` and `%f`.
It defaults to `%# `. `ZSHINKWRAP_RESTORE_DELAY` defaults to `0.20` seconds.

## Test

Install [Bats](https://bats-core.readthedocs.io/), then run:

```sh
bats test/plugin.bats
```

## License

[MIT](LICENSE)
