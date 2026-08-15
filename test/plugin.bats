#!/usr/bin/env bats

setup() {
  export PLUGIN_PATH="$BATS_TEST_DIRNAME/../zshrinkwrap.plugin.zsh"
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
