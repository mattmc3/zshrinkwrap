# Mitigate prompt damage when a terminal reflows text during a resize.

if (( ${_zsh_resize_loaded:-0} )); then
  _zsh_resize_cancel_timer
  _zsh_resize_restore
  unfunction TRAPWINCH
fi
typeset -gi _zsh_resize_loaded=1

typeset -g ZSHINKWRAP_SYMBOL=${ZSHINKWRAP_SYMBOL-'%F{magenta}%#%f '}
typeset -g ZSHINKWRAP_RESTORE_DELAY=${ZSHINKWRAP_RESTORE_DELAY-'0.20'}

zmodload zsh/datetime

typeset -gi _zsh_resize_active=0
typeset -gi _zsh_resize_timer_fd=-1
typeset -gi _zsh_resize_saved_single_line=0
typeset -gF _zsh_resize_deadline=0.0
typeset -g _zsh_resize_saved_prompt
typeset -g _zsh_resize_saved_rprompt

if (( $+functions[TRAPWINCH] && ! $+functions[_zsh_resize_previous_trapwinch] )); then
  functions[_zsh_resize_previous_trapwinch]=$functions[TRAPWINCH]
fi

_zsh_resize_cancel_timer() {
  emulate -L zsh

  if (( _zsh_resize_timer_fd >= 0 )); then
    zle -F $_zsh_resize_timer_fd 2>/dev/null
    exec {_zsh_resize_timer_fd}<&-
    _zsh_resize_timer_fd=-1
  fi
}

_zsh_resize_restore() {
  emulate -L zsh
  (( _zsh_resize_active )) || return 0

  PROMPT=$_zsh_resize_saved_prompt
  RPROMPT=$_zsh_resize_saved_rprompt
  unsetopt localoptions
  if (( _zsh_resize_saved_single_line )); then
    setopt singlelinezle
  else
    unsetopt singlelinezle
  fi
  _zsh_resize_active=0
}

_zsh_resize_timer_ready() {
  emulate -L zsh
  local fd=$1

  zle -F $fd 2>/dev/null
  exec {fd}<&-
  (( fd == _zsh_resize_timer_fd )) || return 0

  _zsh_resize_timer_fd=-1
  local -F remaining=$(( _zsh_resize_deadline - EPOCHREALTIME ))
  if (( remaining > 0.001 )); then
    _zsh_resize_start_timer $remaining
    return 0
  fi

  _zsh_resize_clear_line
  _zsh_resize_restore
  zle reset-prompt
}

_zsh_resize_start_timer() {
  emulate -L zsh
  local delay=${1:-$ZSHINKWRAP_RESTORE_DELAY}

  (( _zsh_resize_timer_fd >= 0 )) && return 0
  exec {_zsh_resize_timer_fd}< <(command sleep "$delay")
  zle -F $_zsh_resize_timer_fd _zsh_resize_timer_ready
}

_zsh_resize_clear_line() {
  emulate -L zsh
  zle -I 2>/dev/null

  if [[ $TERM_PROGRAM == vscode ]]; then
    print -rn -- $'\e8\r\e[0J'
  else
    print -rn -- $'\r\e[2K'
  fi
}

_zsh_resize_mark_prompt() {
  emulate -L zsh
  [[ $TERM_PROGRAM == vscode ]] && print -rn -- $'\e7'
}

_zsh_resize_begin() {
  emulate -L zsh

  if (( ! _zsh_resize_active )); then
    _zsh_resize_saved_prompt=$PROMPT
    _zsh_resize_saved_rprompt=$RPROMPT
    if [[ -o singlelinezle ]]; then
      _zsh_resize_saved_single_line=1
    else
      _zsh_resize_saved_single_line=0
    fi
    _zsh_resize_active=1
  fi

  PROMPT=$ZSHINKWRAP_SYMBOL
  RPROMPT=''
  unsetopt localoptions
  setopt singlelinezle
}

TRAPWINCH() {
  emulate -L zsh
  local trap_status=0

  if (( $+functions[_zsh_resize_previous_trapwinch] )); then
    _zsh_resize_previous_trapwinch || trap_status=$?
  fi

  if zle 2>/dev/null; then
    _zsh_resize_clear_line
    _zsh_resize_begin
    zle reset-prompt
    (( _zsh_resize_deadline = EPOCHREALTIME + ZSHINKWRAP_RESTORE_DELAY ))
    _zsh_resize_start_timer
  fi

  return $trap_status
}

autoload -Uz add-zsh-hook
add-zsh-hook precmd _zsh_resize_restore
add-zsh-hook precmd _zsh_resize_mark_prompt
# https://github.com/romkatv/powerlevel10k#horrific-mess-when-resizing-terminal-window
