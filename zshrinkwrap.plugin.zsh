# Mitigate prompt damage when a terminal reflows text during a resize.

if (( ${_zshrinkwrap_loaded:-0} )); then
  _zshrinkwrap_cancel_timer
  _zshrinkwrap_restore
  if (( $+functions[_zshrinkwrap_previous_trapwinch] )); then
    functions[TRAPWINCH]=$functions[_zshrinkwrap_previous_trapwinch]
    unfunction _zshrinkwrap_previous_trapwinch
  else
    unfunction TRAPWINCH 2>/dev/null
  fi
fi
typeset -gi _zshrinkwrap_loaded=1

typeset -g ZSHRINKWRAP_SYMBOL=${ZSHRINKWRAP_SYMBOL-'%F{magenta}%#%f '}
typeset -g ZSHRINKWRAP_RESTORE_DELAY=${ZSHRINKWRAP_RESTORE_DELAY-'0.20'}

zmodload zsh/datetime

typeset -gi _zshrinkwrap_active=0
typeset -gi _zshrinkwrap_timer_fd=-1
typeset -gi _zshrinkwrap_saved_single_line=0
typeset -gi _zshrinkwrap_last_cols=${COLUMNS:-80}
typeset -gF _zshrinkwrap_deadline=0.0
typeset -g _zshrinkwrap_saved_prompt
typeset -g _zshrinkwrap_saved_rprompt

if (( $+functions[TRAPWINCH] && ! $+functions[_zshrinkwrap_previous_trapwinch] )); then
  functions[_zshrinkwrap_previous_trapwinch]=$functions[TRAPWINCH]
fi

_zshrinkwrap_cancel_timer() {
  emulate -L zsh

  if (( _zshrinkwrap_timer_fd >= 0 )); then
    zle -F $_zshrinkwrap_timer_fd 2>/dev/null
    exec {_zshrinkwrap_timer_fd}<&-
    _zshrinkwrap_timer_fd=-1
  fi
}

_zshrinkwrap_restore() {
  emulate -L zsh
  _zshrinkwrap_cancel_timer
  (( _zshrinkwrap_active )) || return 0

  PROMPT=$_zshrinkwrap_saved_prompt
  RPROMPT=$_zshrinkwrap_saved_rprompt
  unsetopt localoptions
  if (( _zshrinkwrap_saved_single_line )); then
    setopt singlelinezle
  else
    unsetopt singlelinezle
  fi
  _zshrinkwrap_active=0
}

# Estimate physical rows between the top of the prompt display and the
# cursor after the terminal rewraps the display to `cols` columns.
_zshrinkwrap_rows_above() {
  emulate -L zsh
  local prompt=$1
  local -i cols=$2 cursor=$3 rows=0 len i
  local zero='%([BSUbfksu]|([FK]|){*})'
  local -a lines=( "${(@f)${(S%%)prompt//$~zero/}}" )

  (( cols > 0 )) || cols=80
  for (( i = 1; i < $#lines; i++ )); do
    len=${#lines[i]}
    (( rows += (len > 0 ? (len - 1) / cols : 0) + 1 ))
  done
  (( rows += (${#lines[-1]} + cursor) / cols ))
  typeset -g REPLY=$rows
}

# Clear every row the reflowed display may occupy, leaving the cursor at
# the start of the region so the next redraw lands there. Assumes the
# terminal rewraps soft-wrapped lines to the new width, which modern
# terminals (iTerm2, VS Code, kitty, VTE, WezTerm) do.
_zshrinkwrap_clear_display() {
  emulate -L zsh
  local -i rows cap

  zle -I 2>/dev/null
  _zshrinkwrap_rows_above "$PROMPT" ${COLUMNS:-80} ${CURSOR:-0}
  rows=$REPLY

  if (( _zshrinkwrap_active && COLUMNS > 0 )); then
    # Single-line editing kept the display within the previous width, so
    # the rewrapped region cannot span more rows than that width allows.
    (( cap = (_zshrinkwrap_last_cols - 1) / COLUMNS ))
    (( rows > cap )) && rows=cap
  fi
  (( rows > LINES - 1 )) && rows=$(( LINES - 1 ))

  (( rows > 0 )) && print -rn -- $'\e['${rows}'A'
  print -rn -- $'\r\e[0J'
}

_zshrinkwrap_timer_ready() {
  emulate -L zsh
  local fd=$1

  zle -F $fd 2>/dev/null
  exec {fd}<&-
  (( fd == _zshrinkwrap_timer_fd )) || return 0

  _zshrinkwrap_timer_fd=-1
  local -F remaining=$(( _zshrinkwrap_deadline - EPOCHREALTIME ))
  if (( remaining > 0.001 )); then
    _zshrinkwrap_start_timer $remaining
    return 0
  fi

  (( _zshrinkwrap_active )) || return 0
  _zshrinkwrap_clear_display
  _zshrinkwrap_restore
  zle reset-prompt
}

_zshrinkwrap_start_timer() {
  emulate -L zsh
  local delay=${1:-$ZSHRINKWRAP_RESTORE_DELAY}

  (( _zshrinkwrap_timer_fd >= 0 )) && return 0
  exec {_zshrinkwrap_timer_fd}< <(command sleep "$delay")
  zle -F $_zshrinkwrap_timer_fd _zshrinkwrap_timer_ready
}

_zshrinkwrap_begin() {
  emulate -L zsh

  if (( ! _zshrinkwrap_active )); then
    _zshrinkwrap_saved_prompt=$PROMPT
    _zshrinkwrap_saved_rprompt=$RPROMPT
    if [[ -o singlelinezle ]]; then
      _zshrinkwrap_saved_single_line=1
    else
      _zshrinkwrap_saved_single_line=0
    fi
    _zshrinkwrap_active=1
  fi

  PROMPT=$ZSHRINKWRAP_SYMBOL
  RPROMPT=''
  unsetopt localoptions
  setopt singlelinezle
}

TRAPWINCH() {
  emulate -L zsh
  local trap_status=0

  if (( $+functions[_zshrinkwrap_previous_trapwinch] )); then
    _zshrinkwrap_previous_trapwinch || trap_status=$?
  fi

  if zle 2>/dev/null; then
    _zshrinkwrap_clear_display
    _zshrinkwrap_begin
    zle reset-prompt
    _zshrinkwrap_last_cols=${COLUMNS:-80}
    (( _zshrinkwrap_deadline = EPOCHREALTIME + ZSHRINKWRAP_RESTORE_DELAY ))
    _zshrinkwrap_start_timer
  fi

  return $trap_status
}

autoload -Uz add-zsh-hook
add-zsh-hook precmd _zshrinkwrap_restore
# https://github.com/romkatv/powerlevel10k#horrific-mess-when-resizing-terminal-window
