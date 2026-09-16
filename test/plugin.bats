#!/usr/bin/env bats

setup() {
  export PLUGIN_PATH="$BATS_TEST_DIRNAME/../zshrinkwrap.plugin.zsh"
  # Terminal detection picks the strategy, so tests must not inherit one.
  export TERM_PROGRAM=
}

@test "uses responsive defaults" {
  run zsh -fc '
    source "$PLUGIN_PATH"
    _zshrinkwrap_style symbol
    [[ $REPLY == "%F{magenta}%#%f " ]]
    _zshrinkwrap_style restore-delay
    [[ $REPLY == 0.20 ]]
  '

  [ "$status" -eq 0 ]
}

@test "falls back to the default when a style is empty" {
  run zsh -fc '
    zstyle ":zshrinkwrap:resize" symbol ""
    zstyle ":zshrinkwrap:resize" restore-delay ""
    source "$PLUGIN_PATH"
    _zshrinkwrap_style symbol
    [[ $REPLY == "%F{magenta}%#%f " ]]
    _zshrinkwrap_style restore-delay
    [[ $REPLY == 0.20 ]]
  '

  [ "$status" -eq 0 ]
}

@test "supports prompt color escapes in symbol" {
  run zsh -fc '
    zstyle ":zshrinkwrap:resize" symbol "%F{magenta}❯%f "
    zstyle ":zshrinkwrap:resize" shrink-lprompt yes
    source "$PLUGIN_PATH"
    zle() { return 0 }

    _zshrinkwrap_adjust

    [[ $PROMPT == "%F{magenta}❯%f " ]]
    expanded_prompt=${(%)PROMPT}
    [[ $expanded_prompt != $PROMPT ]]
    [[ $expanded_prompt == *❯* ]]
  '

  [ "$status" -eq 0 ]
}

@test "counts zero rows for a short unwrapped line" {
  run zsh -fc '
    source "$PLUGIN_PATH"
    _zshrinkwrap_rows_above "abc> " 80 10
    [[ $REPLY == 0 ]]
  '

  [ "$status" -eq 0 ]
}

@test "counts rows when the edit line wraps" {
  run zsh -fc '
    source "$PLUGIN_PATH"
    _zshrinkwrap_rows_above "abc> " 10 20
    [[ $REPLY == 2 ]]
  '

  [ "$status" -eq 0 ]
}

@test "counts extra prompt lines and their wraps" {
  run zsh -fc '
    source "$PLUGIN_PATH"
    _zshrinkwrap_rows_above "123456789012345"$'\n'"abc> " 10 0
    [[ $REPLY == 2 ]]
  '

  [ "$status" -eq 0 ]
}

@test "ignores zero-width prompt escapes when measuring" {
  run zsh -fc '
    source "$PLUGIN_PATH"
    _zshrinkwrap_rows_above "%F{magenta}12345%f" 10 8
    [[ $REPLY == 1 ]]
  '

  [ "$status" -eq 0 ]
}

@test "picks split strategy in VS Code" {
  run zsh -fc '
    TERM_PROGRAM=vscode
    source "$PLUGIN_PATH"
    _zshrinkwrap_strategy
    [[ $REPLY == split ]]
  '

  [ "$status" -eq 0 ]
}

@test "picks split strategy in Apple Terminal" {
  run zsh -fc '
    TERM_PROGRAM=Apple_Terminal
    source "$PLUGIN_PATH"
    _zshrinkwrap_strategy
    [[ $REPLY == split ]]
  '

  [ "$status" -eq 0 ]
}

@test "split prints upper prompt lines and leaves zle the last line" {
  run zsh -fc '
    zstyle ":zshrinkwrap:resize" strategy split
    source "$PLUGIN_PATH"
    PROMPT=$'"'"'top %F{red}line%f\n> '"'"'

    out=$(_zshrinkwrap_split_precmd; print -rn -- "|${(%)PROMPT}")
    [[ $out == $'"'"'top \e[31mline\e[39m\n|> '"'"' ]] || { print -r -- ${(q+)out}; exit 1 }
  '

  [ "$status" -eq 0 ]
}

@test "split records display widths of upper prompt lines" {
  run zsh -fc '
    zstyle ":zshrinkwrap:resize" strategy split
    source "$PLUGIN_PATH"
    PROMPT=$'"'"'%F{red}abc%f\nde\n> '"'"'

    _zshrinkwrap_split_precmd >/dev/null
    [[ ${_zshrinkwrap_upper_widths[*]} == "3 2" ]]
  '

  [ "$status" -eq 0 ]
}

@test "split leaves a single-line prompt alone" {
  run zsh -fc '
    zstyle ":zshrinkwrap:resize" strategy split
    source "$PLUGIN_PATH"
    PROMPT="%~ %# "

    out=$(_zshrinkwrap_split_precmd)
    _zshrinkwrap_split_precmd
    [[ -z $out && $PROMPT == "%~ %# " ]]
  '

  [ "$status" -eq 0 ]
}

@test "split evaluates prompt_subst prompts before splitting" {
  run zsh -fc '
    zstyle ":zshrinkwrap:resize" strategy split
    source "$PLUGIN_PATH"
    setopt prompt_subst
    integer calls=0
    count() { (( ++calls )); print -rn -- "n$calls" }
    PROMPT=$'"'"'$(count) top\n> '"'"'

    _zshrinkwrap_split_precmd >/dev/null
    [[ ${(%%)PROMPT} == "> " ]]
  '

  [ "$status" -eq 0 ]
}

@test "split gives the original prompt back before each command" {
  run zsh -fc '
    zstyle ":zshrinkwrap:resize" strategy split
    source "$PLUGIN_PATH"
    PROMPT=$'"'"'top\n> '"'"'

    _zshrinkwrap_split_precmd >/dev/null
    _zshrinkwrap_split_preexec
    [[ $PROMPT == $'"'"'top\n> '"'"' ]]
  '

  [ "$status" -eq 0 ]
}

@test "split keeps the original prompt across prompts" {
  run zsh -fc '
    zstyle ":zshrinkwrap:resize" strategy split
    source "$PLUGIN_PATH"
    PROMPT=$'"'"'top\n> '"'"'

    _zshrinkwrap_split_precmd >/dev/null
    out=$(_zshrinkwrap_split_precmd)
    [[ $out == top ]]
  '

  [ "$status" -eq 0 ]
}

@test "split collapses both prompts on resize regardless of shrink styles" {
  run zsh -fc '
    zstyle ":zshrinkwrap:resize" strategy split
    zstyle ":zshrinkwrap:resize" shrink-lprompt no
    zstyle ":zshrinkwrap:resize" shrink-rprompt no
    source "$PLUGIN_PATH"
    PROMPT="wide prompt > "
    RPROMPT="right prompt"
    zle() { return 0 }

    out=$(_zshrinkwrap_adjust)
    _zshrinkwrap_adjust
    [[ -z $out ]]
    [[ $PROMPT == "%F{magenta}%#%f " && -z $RPROMPT ]]
  '

  [ "$status" -eq 0 ]
}

@test "split redraw climbs the upper lines from the cursor row and clears" {
  run zsh -fc '
    zstyle ":zshrinkwrap:resize" strategy split
    source "$PLUGIN_PATH"
    PROMPT=$'"'"'0123456789\n> '"'"'
    zle() { return 0 }

    _zshrinkwrap_split_precmd >/dev/null
    _zshrinkwrap_adjust
    COLUMNS=4
    _zshrinkwrap_split_redraw | head -c 9 | od -An -tx1 | tr -d " \n"
  '

  [ "$status" -eq 0 ]
  [ "$output" = "1b5b33410d1b5b304a" ]
}

@test "picks none strategy in Ghostty with shell integration" {
  run zsh -fc '
    TERM_PROGRAM=ghostty
    source "$PLUGIN_PATH"
    _ghostty_precmd() { : }
    _zshrinkwrap_strategy
    [[ $REPLY == none ]]
  '

  [ "$status" -eq 0 ]
}

@test "picks estimate strategy in Ghostty without shell integration" {
  run zsh -fc '
    TERM_PROGRAM=ghostty
    source "$PLUGIN_PATH"
    _zshrinkwrap_strategy
    [[ $REPLY == estimate ]]
  '

  [ "$status" -eq 0 ]
}

@test "picks estimate strategy in other terminals" {
  run zsh -fc '
    TERM_PROGRAM=iTerm.app
    source "$PLUGIN_PATH"
    _zshrinkwrap_strategy
    [[ $REPLY == estimate ]]
  '

  [ "$status" -eq 0 ]
}

@test "strategy style overrides terminal detection" {
  run zsh -fc '
    TERM_PROGRAM=vscode
    zstyle ":zshrinkwrap:resize" strategy none
    source "$PLUGIN_PATH"
    _zshrinkwrap_strategy
    [[ $REPLY == none ]]
  '

  [ "$status" -eq 0 ]
}

@test "none strategy leaves prompts and display alone on resize" {
  run zsh -fc '
    zstyle ":zshrinkwrap:resize" strategy none
    source "$PLUGIN_PATH"
    PROMPT="wide prompt > "
    RPROMPT="right prompt"
    zle() { return 0 }

    out=$(TRAPWINCH)
    TRAPWINCH >/dev/null
    [[ -z $out ]]
    [[ $PROMPT == "wide prompt > " && $RPROMPT == "right prompt" ]]
    [[ $_zshrinkwrap_timer_fd -eq -1 ]]
  '

  [ "$status" -eq 0 ]
}

@test "climbs to the reflowed top by default" {
  run zsh -fc '
    TERM_PROGRAM=
    source "$PLUGIN_PATH"
    zle() { return 0 }
    COLUMNS=10; LINES=24; CURSOR=20; PROMPT="abc> "
    _zshrinkwrap_last_cols=80

    _zshrinkwrap_adjust | od -An -tx1 | tr -d " \n"
  '

  [ "$status" -eq 0 ]
  [ "$output" = "1b5b3241" ]
}

@test "can disable the reflow climb" {
  run zsh -fc '
    TERM_PROGRAM=
    zstyle ":zshrinkwrap:resize" reflow no
    source "$PLUGIN_PATH"
    zle() { return 0 }
    COLUMNS=10; LINES=24; CURSOR=20; PROMPT="abc> "
    _zshrinkwrap_last_cols=80

    _zshrinkwrap_adjust | od -An -tx1 | tr -d " \n"
  '

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "preserves an existing WINCH trap" {
  run zsh -fc '
    TRAPWINCH() { return 23 }
    source "$PLUGIN_PATH"
    TRAPWINCH
  '

  [ "$status" -eq 23 ]
}

@test "can be sourced more than once" {
  run zsh -fc '
    TRAPWINCH() { return 23 }
    source "$PLUGIN_PATH"
    trap_body=$functions[TRAPWINCH]
    source "$PLUGIN_PATH"
    [[ $functions[TRAPWINCH] == $trap_body ]]
    TRAPWINCH
  '

  [ "$status" -eq 23 ]
}

@test "keeps left prompt and shrinks right prompt by default" {
  run zsh -fc '
    source "$PLUGIN_PATH"
    PROMPT="wide prompt > "
    RPROMPT="right prompt"
    zle() { return 0 }

    _zshrinkwrap_adjust

    [[ $PROMPT == "wide prompt > " && -z $RPROMPT ]]
  '

  [ "$status" -eq 0 ]
}

@test "can shrink left prompt during resize" {
  run zsh -fc '
    zstyle ":zshrinkwrap:resize" shrink-lprompt true
    source "$PLUGIN_PATH"
    PROMPT="wide prompt > "
    RPROMPT="right prompt"
    zle() { return 0 }

    _zshrinkwrap_adjust

    [[ $PROMPT == "%F{magenta}%#%f " && -z $RPROMPT ]]
  '

  [ "$status" -eq 0 ]
}

@test "can keep right prompt during resize" {
  run zsh -fc '
    zstyle ":zshrinkwrap:resize" shrink-rprompt no
    source "$PLUGIN_PATH"
    PROMPT="wide prompt > "
    RPROMPT="right prompt"
    zle() { return 0 }

    _zshrinkwrap_adjust

    [[ $PROMPT == "wide prompt > " &&
       $RPROMPT == "right prompt" ]]
  '

  [ "$status" -eq 0 ]
}

@test "restores prompt and editor mode" {
  run zsh -fc '
    unsetopt singlelinezle
    source "$PLUGIN_PATH"
    PROMPT="wide prompt > "
    RPROMPT="right prompt"

    zle() { return 0 }
    _zshrinkwrap_adjust
    _zshrinkwrap_restore

    [[ $PROMPT == "wide prompt > " ]]
    [[ $RPROMPT == "right prompt" ]]
    [[ ! -o singlelinezle ]]
  '

  [ "$status" -eq 0 ]
}

@test "preserves an existing single-line editor setting" {
  run zsh -fc '
    setopt singlelinezle
    source "$PLUGIN_PATH"
    zle() { return 0 }

    _zshrinkwrap_adjust
    _zshrinkwrap_restore

    [[ -o singlelinezle ]]
  '

  [ "$status" -eq 0 ]
}

@test "repeated resize does not save compact prompt" {
  run zsh -fc '
    source "$PLUGIN_PATH"
    PROMPT="wide prompt > "
    RPROMPT="right prompt"
    zle() { return 0 }

    _zshrinkwrap_adjust
    _zshrinkwrap_adjust
    _zshrinkwrap_restore

    [[ $PROMPT == "wide prompt > " ]]
    [[ $RPROMPT == "right prompt" ]]
  '

  [ "$status" -eq 0 ]
}

@test "repeated resize reuses the active timer" {
  run zsh -fc '
    source "$PLUGIN_PATH"
    integer timer_cancellations=0
    _zshrinkwrap_cancel_timer() { (( ++timer_cancellations )) }
    zle() { return 0 }

    _zshrinkwrap_start_timer
    _zshrinkwrap_start_timer

    exec {_zshrinkwrap_timer_fd}<&-
    [[ $timer_cancellations == 0 ]]
  '

  [ "$status" -eq 0 ]
}

@test "restore cancels a pending timer" {
  run zsh -fc '
    source "$PLUGIN_PATH"
    zle() { return 0 }

    _zshrinkwrap_adjust
    _zshrinkwrap_start_timer 0.20
    [[ $_zshrinkwrap_timer_fd -ge 0 ]]

    _zshrinkwrap_restore
    [[ $_zshrinkwrap_timer_fd -eq -1 ]]
  '

  [ "$status" -eq 0 ]
}

@test "stale timer does not clear or redraw" {
  run zsh -fc '
    source "$PLUGIN_PATH"
    zle() { return 0 }

    exec {fd}< /dev/null
    _zshrinkwrap_timer_fd=$fd
    _zshrinkwrap_deadline=0

    out=$(_zshrinkwrap_timer_ready $fd)
    [[ -z $out ]]
  '

  [ "$status" -eq 0 ]
}
