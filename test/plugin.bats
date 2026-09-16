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

@test "split draws the right prompt with autowrap off" {
  run zsh -fc '
    zstyle ":zshrinkwrap:resize" strategy split
    source "$PLUGIN_PATH"
    PROMPT="> "
    RPROMPT="right"

    _zshrinkwrap_split_precmd
    [[ $RPROMPT == $'"'"'%{\e[?7l%}right%{\e[?7h%}'"'"' ]] || exit 1
    _zshrinkwrap_split_precmd
    [[ $RPROMPT == $'"'"'%{\e[?7l%}right%{\e[?7h%}'"'"' ]] || exit 2
    _zshrinkwrap_split_preexec
    [[ $RPROMPT == right ]] || exit 3
  '

  [ "$status" -eq 0 ]
}

@test "split leaves an empty right prompt alone" {
  run zsh -fc '
    zstyle ":zshrinkwrap:resize" strategy split
    source "$PLUGIN_PATH"
    PROMPT="> "
    RPROMPT=

    _zshrinkwrap_split_precmd
    [[ -z $RPROMPT ]]
  '

  [ "$status" -eq 0 ]
}

@test "split cooperates with a prompt wrapper added before the plugin" {
  run zsh -fc '
    zstyle ":zshrinkwrap:resize" strategy split
    # Stand-in for integrations that wrap PROMPT at precmd and restore it
    # in preexec, like wezterm.sh.
    wrap_precmd() { saved=$PROMPT; PROMPT="<$PROMPT>"; check=$PROMPT }
    wrap_preexec() { [[ $PROMPT == $check ]] && PROMPT=$saved }
    printed=$(mktemp)
    trap "rm -f $printed" EXIT
    cycle() {
      local f
      for f in $precmd_functions; do $f; done >>$printed
      prompts+=( "$PROMPT" )
      for f in $preexec_functions; do $f; done
    }
    precmd_functions=( wrap_precmd )
    preexec_functions=( wrap_preexec )
    source "$PLUGIN_PATH"
    PROMPT=$'"'"'top\n> '"'"'

    cycle; cycle; cycle
    [[ $PROMPT == $'"'"'top\n> '"'"' ]] || exit 1
    [[ $(grep -c "top" $printed) -ge 2 ]] || exit 2
    [[ ${prompts[-1]} != *"<<"* ]] || exit 3
  '

  [ "$status" -eq 0 ]
}

@test "split cooperates with a prompt wrapper added after the plugin" {
  run zsh -fc '
    zstyle ":zshrinkwrap:resize" strategy split
    # Stand-in for integrations that wrap PROMPT at precmd and restore it
    # in preexec, like wezterm.sh.
    wrap_precmd() { saved=$PROMPT; PROMPT="<$PROMPT>"; check=$PROMPT }
    wrap_preexec() { [[ $PROMPT == $check ]] && PROMPT=$saved }
    printed=$(mktemp)
    trap "rm -f $printed" EXIT
    cycle() {
      local f
      for f in $precmd_functions; do $f; done >>$printed
      prompts+=( "$PROMPT" )
      for f in $preexec_functions; do $f; done
    }
    source "$PLUGIN_PATH"
    precmd_functions+=( wrap_precmd )
    preexec_functions+=( wrap_preexec )
    PROMPT=$'"'"'top\n> '"'"'

    cycle; cycle; cycle
    [[ $PROMPT == $'"'"'top\n> '"'"' ]] || exit 1
    [[ $(grep -c "top" $printed) -ge 2 ]] || exit 2
    [[ ${prompts[-1]} != *"<<"* ]] || exit 3
  '

  [ "$status" -eq 0 ]
}

@test "split cooperates with a wrapper that restores without checking" {
  run zsh -fc '
    zstyle ":zshrinkwrap:resize" strategy split
    # Like the iTerm2 integration, which restores PS1 in preexec unconditionally.
    wrap_precmd() { saved=$PROMPT; PROMPT="<$PROMPT>" }
    wrap_preexec() { PROMPT=$saved }
    printed=$(mktemp)
    trap "rm -f $printed" EXIT
    cycle() {
      local f
      for f in $precmd_functions; do $f; done >>$printed
      prompts+=( "$PROMPT" )
      for f in $preexec_functions; do $f; done
    }
    source "$PLUGIN_PATH"
    precmd_functions+=( wrap_precmd )
    preexec_functions+=( wrap_preexec )
    PROMPT=$'"'"'top\n> '"'"'

    cycle; cycle; cycle
    [[ $PROMPT == $'"'"'top\n> '"'"' ]] || exit 1
    [[ $(grep -c "top" $printed) -ge 2 ]] || exit 2
    [[ ${prompts[-1]} != *"<<"* ]] || exit 3
  '

  [ "$status" -eq 0 ]
}

@test "split still splits beside a hook that insists on running last" {
  run zsh -fc '
    zstyle ":zshrinkwrap:resize" strategy split
    # Like Ghostty and kitty integrations, which move themselves last.
    last_precmd() {
      precmd_functions=( ${precmd_functions:#last_precmd} last_precmd )
    }
    printed=$(mktemp)
    trap "rm -f $printed" EXIT
    cycle() {
      local f
      for f in $precmd_functions; do $f; done >>$printed
      for f in $preexec_functions; do $f; done
    }
    source "$PLUGIN_PATH"
    precmd_functions+=( last_precmd )
    PROMPT=$'"'"'top\n> '"'"'

    cycle; cycle; cycle; cycle
    [[ $(grep -c "top" $printed) -ge 2 ]] || exit 1
    [[ $PROMPT == $'"'"'top\n> '"'"' ]] || exit 2
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

@test "picks none strategy in kitty with shell integration" {
  run zsh -fc '
    TERM=xterm-kitty
    source "$PLUGIN_PATH"
    _ksi_precmd() { : }
    _zshrinkwrap_strategy
    [[ $REPLY == none ]]
  '

  [ "$status" -eq 0 ]
}

@test "picks none strategy in kitty before its integration initializes" {
  run zsh -fc '
    TERM=xterm-kitty
    source "$PLUGIN_PATH"
    _ksi_deferred_init() { : }
    _zshrinkwrap_strategy
    [[ $REPLY == none ]]
  '

  [ "$status" -eq 0 ]
}

@test "picks split strategy in kitty without shell integration" {
  run zsh -fc '
    TERM=xterm-kitty
    source "$PLUGIN_PATH"
    _zshrinkwrap_strategy
    [[ $REPLY == split ]]
  '

  [ "$status" -eq 0 ]
}

@test "picks split strategy in Ghostty without shell integration" {
  run zsh -fc '
    TERM_PROGRAM=ghostty
    source "$PLUGIN_PATH"
    _zshrinkwrap_strategy
    [[ $REPLY == split ]]
  '

  [ "$status" -eq 0 ]
}

@test "picks split strategy in other terminals" {
  run zsh -fc '
    TERM_PROGRAM=iTerm.app
    source "$PLUGIN_PATH"
    _zshrinkwrap_strategy
    [[ $REPLY == split ]]
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

@test "collapses both prompts on resize without moving the cursor" {
  run zsh -fc '
    source "$PLUGIN_PATH"
    PROMPT="wide prompt > "
    RPROMPT="right prompt"
    COLUMNS=10; LINES=24; CURSOR=20
    zle() { return 0 }

    out=$(_zshrinkwrap_adjust)
    _zshrinkwrap_adjust
    [[ -z $out ]]
    [[ $PROMPT == "%F{magenta}%#%f " && -z $RPROMPT ]]
  '

  [ "$status" -eq 0 ]
}

@test "keeps syntax highlighting across a stashed command" {
  run zsh -fc '
    source "$PLUGIN_PATH"
    BUFFER="echo hi"
    CURSOR=7
    region_highlight=( "0 4 fg=green" )
    zle() {
      case $1 in
        push-line) _stash=$BUFFER; BUFFER=; region_highlight=() ;;
        get-line) BUFFER=$_stash ;;
      esac
      return 0
    }

    _zshrinkwrap_adjust
    [[ -z $BUFFER ]] || exit 1
    _zshrinkwrap_restore
    [[ $BUFFER == "echo hi" ]] || exit 2
    [[ ${region_highlight[*]} == "0 4 fg=green" ]] || exit 3
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

@test "timer handler runs as a widget so zle state is live" {
  run zsh -fc '
    source "$PLUGIN_PATH"
    zle() { [[ $1 == -F ]] && print -r -- "$*" }

    _zshrinkwrap_start_timer 0.01 | grep -q -- "-F -w [0-9]* _zshrinkwrap_timer_ready"
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
