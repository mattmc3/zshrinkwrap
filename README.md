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

## Terminal compatibility

Ghostty, Apple Terminal, WezTerm, and iTerm2 use the default single-row cleanup.
VS Code needs stronger handling because xterm.js can move prompt fragments onto
other rows before Zsh receives `SIGWINCH`.

For terminals like VS Code, zshrinkwrap saves the cursor position before drawing
each prompt. During resize it returns to that saved prompt origin, clears the
reflowed prompt area, and asks ZLE to redraw from its preserved buffer.

This cursor-marker method is intentionally limited to VS Code. It is less safe
as a generic fallback because:

- some terminals reflow text without reflowing the saved cursor position;
- terminals provide one shared saved-cursor slot that another program can
  overwrite;
- output from a later `precmd` hook can make the saved origin stale; and
- tmux or screen can change cursor and resize behavior between Zsh and the
  outer terminal.

Restoring a stale cursor before clearing could erase unrelated visible output.
New terminals should use this path only after manual testing confirms that their
saved cursor follows text during resize. This is the same compatibility
requirement described by the Powerlevel10k
[Zsh patch discussion](https://github.com/romkatv/powerlevel10k#zsh-patch).

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
It defaults to `%F{magenta}%#%f `. `ZSHINKWRAP_RESTORE_DELAY` defaults to `0.20`
seconds.

## Test

Install [Bats](https://bats-core.readthedocs.io/), then run:

```sh
bats test/plugin.bats
```

## License

[MIT](LICENSE)
