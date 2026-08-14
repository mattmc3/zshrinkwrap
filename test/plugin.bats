#!/usr/bin/env bats

setup() {
  export PLUGIN_PATH="$BATS_TEST_DIRNAME/../zshrinkwrap.plugin.zsh"
}

@test "uses responsive defaults" {
  run zsh -fc '
    source "$PLUGIN_PATH"
    [[ $ZSHINKWRAP_SYMBOL == "%# " ]]
    [[ $ZSHINKWRAP_RESTORE_DELAY == 0.20 ]]
  '

  [ "$status" -eq 0 ]
}

@test "supports prompt color escapes in symbol" {
  run zsh -fc '
    ZSHINKWRAP_SYMBOL="%F{magenta}❯%f "
    source "$PLUGIN_PATH"

    _zsh_resize_begin

    [[ $PROMPT == "%F{magenta}❯%f " ]]
    expanded_prompt=${(%)PROMPT}
    [[ $expanded_prompt != $PROMPT ]]
    [[ $expanded_prompt == *❯* ]]
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

@test "uses compact prompt and single-line editor during resize" {
  run zsh -fc '
    unsetopt singlelinezle
    source "$PLUGIN_PATH"
    PROMPT="wide prompt > "
    RPROMPT="right prompt"

    _zsh_resize_begin

    [[ $PROMPT == "%# " ]]
    [[ -z $RPROMPT ]]
    [[ -o singlelinezle ]]
  '

  [ "$status" -eq 0 ]
}

@test "restores prompt and editor mode" {
  run zsh -fc '
    unsetopt singlelinezle
    source "$PLUGIN_PATH"
    PROMPT="wide prompt > "
    RPROMPT="right prompt"

    _zsh_resize_begin
    _zsh_resize_restore

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

    _zsh_resize_begin
    _zsh_resize_restore

    [[ -o singlelinezle ]]
  '

  [ "$status" -eq 0 ]
}

@test "repeated resize does not save compact prompt" {
  run zsh -fc '
    source "$PLUGIN_PATH"
    PROMPT="wide prompt > "
    RPROMPT="right prompt"

    _zsh_resize_begin
    _zsh_resize_begin
    _zsh_resize_restore

    [[ $PROMPT == "wide prompt > " ]]
    [[ $RPROMPT == "right prompt" ]]
  '

  [ "$status" -eq 0 ]
}

@test "repeated resize reuses the active timer" {
  run zsh -fc '
    source "$PLUGIN_PATH"
    integer timer_cancellations=0
    _zsh_resize_cancel_timer() { (( ++timer_cancellations )) }
    zle() { return 0 }

    _zsh_resize_start_timer
    _zsh_resize_start_timer

    exec {_zsh_resize_timer_fd}<&-
    [[ $timer_cancellations == 0 ]]
  '

  [ "$status" -eq 0 ]
}
