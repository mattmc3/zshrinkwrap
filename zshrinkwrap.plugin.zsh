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
typeset -gi _zshrinkwrap_pushed=0
typeset -gi _zshrinkwrap_hard=0
typeset -gi _zshrinkwrap_timer_fd=-1
typeset -gi _zshrinkwrap_last_cols=${COLUMNS:-80}
typeset -gi _zshrinkwrap_saved_cursor=0
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
  _zshrinkwrap_last_cols=${COLUMNS:-80}
  (( _zshrinkwrap_active )) || return 0

  PROMPT=$_zshrinkwrap_saved_prompt
  RPROMPT=$_zshrinkwrap_saved_rprompt
  _zshrinkwrap_active=0

  # Only reclaim the stashed edit line while still at the same prompt.
  # After accept-line zsh pops the buffer stack itself at the next prompt.
  if (( _zshrinkwrap_pushed )) && zle 2>/dev/null; then
    zle get-line
    (( CURSOR = _zshrinkwrap_saved_cursor < $#BUFFER ?
                _zshrinkwrap_saved_cursor : $#BUFFER ))
    _zshrinkwrap_pushed=0
  fi
}

# Estimate physical rows between the top of the prompt display and the
# cursor when the display is wrapped to `cols` columns.
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

# Runs inside TRAPWINCH. Before the trap, zsh redraws the display at the
# new width, but it climbs to the old top using a row offset computed at
# the old width, while the terminal's reflow moved the cursor to the new
# width's offset. The drawing therefore lands delta rows off. Zsh then
# parks the cursor on a fresh row below its drawing, and the end-of-trap
# refresh climbs that same parked depth and clears with ED from there. So
# a single cursor-up of delta rows makes that refresh land on the true
# top, wiping both the stale rows and the displaced drawing.
_zshrinkwrap_adjust() {
  emulate -L zsh
  local -i r_old r_new delta

  if [[ $TERM_PROGRAM == vscode ]]; then
    # xterm.js moves the saved cursor along with reflowed text, so DECRC
    # returns to the prompt origin marked at precmd: an absolute anchor,
    # immune to history lines above the prompt rewrapping. Wipe from the
    # origin, then descend the parked depth so the end-of-trap refresh
    # climbs back onto the origin.
    local -i len=${#BUFFER} parked
    _zshrinkwrap_rows_above "$PROMPT" ${COLUMNS:-80} $(( len > 0 ? len - 1 : 0 ))
    parked=$(( REPLY + 1 ))
    (( parked > LINES - 1 )) && parked=$(( LINES - 1 ))
    print -rn -- $'\e8\r\e[0J\e['${parked}'B'
  elif (( ${ZSHRINKWRAP_REFLOW:-1} )); then
    _zshrinkwrap_rows_above "$PROMPT" $_zshrinkwrap_last_cols ${CURSOR:-0}
    r_old=$REPLY
    _zshrinkwrap_rows_above "$PROMPT" ${COLUMNS:-80} ${CURSOR:-0}
    r_new=$REPLY
    (( delta = r_new - r_old ))
    (( delta > LINES - 1 )) && delta=$(( LINES - 1 ))
    (( delta > 0 )) && print -rn -- $'\e['${delta}'A'
  fi

  if (( ! _zshrinkwrap_active )); then
    _zshrinkwrap_saved_prompt=$PROMPT
    _zshrinkwrap_saved_rprompt=$RPROMPT
    _zshrinkwrap_saved_cursor=${CURSOR:-0}
    _zshrinkwrap_active=1

    if [[ -n $BUFFER ]]; then
      zle push-line && _zshrinkwrap_pushed=1
    fi
    PROMPT=$ZSHRINKWRAP_SYMBOL
    RPROMPT=''
  fi
  zle reset-prompt
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

TRAPWINCH() {
  emulate -L zsh
  local trap_status=0

  if (( $+functions[_zshrinkwrap_previous_trapwinch] )); then
    _zshrinkwrap_previous_trapwinch || trap_status=$?
  fi

  if zle 2>/dev/null; then
    _zshrinkwrap_adjust
    (( _zshrinkwrap_deadline = EPOCHREALTIME + ZSHRINKWRAP_RESTORE_DELAY ))
    _zshrinkwrap_start_timer
  fi

  _zshrinkwrap_last_cols=${COLUMNS:-80}
  return $trap_status
}

# Save the cursor at the prompt origin so DECRC can find it after reflow.
# Registered last so other precmd output lands before the mark, but any
# hook added later that prints will still make the saved origin stale.
_zshrinkwrap_mark_origin() {
  [[ $TERM_PROGRAM == vscode ]] && print -rn -- $'\e7'
  return 0
}

autoload -Uz add-zsh-hook
add-zsh-hook precmd _zshrinkwrap_restore
add-zsh-hook precmd _zshrinkwrap_mark_origin
# https://github.com/romkatv/powerlevel10k#horrific-mess-when-resizing-terminal-window
