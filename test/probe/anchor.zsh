# Probe: can a saved-cursor anchor keep the prompt clean through a resize?
# Usage: start `zsh -f`, then: source test/probe/anchor.zsh [oneline|twoline] [auto|collapse|manual]
# auto redraws from the anchor on every WINCH. collapse fixes the anchor on the
# first WINCH, shows a short prompt while resizing, and redraws once it settles.
# manual leaves resizes alone; press Ctrl-G to redraw from the anchor.

source ${${(%):-%x}:A:h}/common.zsh

probe_layout ${1:-oneline} || return 1
typeset -g _probe_mode=${2:-auto}
[[ $_probe_mode == (auto|collapse|manual) ]] || {
  print -u2 -r -- "unknown mode '$_probe_mode' (want auto|collapse|manual)"
  return 1
}
probe_env
print -r -- "layout=${1:-oneline} mode=$_probe_mode; resize, Ctrl-G redraws"

# Display widths of the prompt lines above the cursor line, as last drawn.
typeset -ga _probe_upper=()
typeset -gi _probe_cols=$COLUMNS

# Rows between the top of the prompt display and the cursor at `cols` wide.
_probe_rows_above() {
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

_probe_record() {
  emulate -L zsh -o extendedglob
  local line
  local -a lines=( "${(@f)${(%%)PROMPT}}" )

  _probe_upper=()
  for line in "${(@)lines[1,-2]}"; do
    line=${line//$'\e'\[[0-9;]#m/}
    _probe_upper+=( ${(m)#line} )
  done
  _probe_cols=$COLUMNS
}

# Rows the recorded upper prompt lines take at `cols` wide.
_probe_upper_rows() {
  emulate -L zsh
  local -i cols=$1 rows=0 len

  for len in $_probe_upper; do
    (( rows += len > 0 ? (len + cols - 1) / cols : 1 ))
  done
  typeset -g REPLY=$rows
}

_probe_anchor_mark() {
  if (( _probe_collapsed )); then
    PROMPT=$_probe_saved_prompt
    RPROMPT=$_probe_saved_rprompt
    _probe_collapsed=0
  fi
  print -rn -- $'\e7'
  _probe_record
}

# Restore the anchor, clear below it, and step down `park` rows so zle's
# redraw climbs back onto it. Line feeds scroll instead of clamping.
_probe_redraw_from_anchor() {
  emulate -L zsh
  local -i park=$1

  print -rn -- $'\e8\r\e[0J'
  (( park > 0 )) && print -rn -- ${(pl:park::\n:)}
  zle reset-prompt
  _probe_record
}

_probe_anchor_widget() {
  emulate -L zsh
  _probe_rows_above "$PROMPT" $COLUMNS $CURSOR
  _probe_redraw_from_anchor $REPLY
}

# xterm.js shifts the saved row by every row reflow adds, including wrapped
# prompt lines below it, so undo that part and save the corrected anchor.
_probe_fix_anchor() {
  emulate -L zsh
  local -i old delta

  _probe_upper_rows $_probe_cols
  old=$REPLY
  _probe_upper_rows $COLUMNS
  (( delta = REPLY - old ))
  print -rn -- $'\e8'
  (( delta > 0 )) && print -rn -- $'\e['$delta'A'
  (( delta < 0 )) && print -rn -- $'\e['$(( -delta ))'B'
  print -rn -- $'\e7'
}

typeset -gi _probe_collapsed=0 _probe_timer_fd=-1
typeset -g _probe_saved_prompt _probe_saved_rprompt

_probe_settle() {
  emulate -L zsh
  local fd=$1

  zle -F $fd 2>/dev/null
  exec {fd}<&-
  (( fd == _probe_timer_fd )) || return 0
  _probe_timer_fd=-1

  _probe_fix_anchor
  _probe_rows_above "$PROMPT" $COLUMNS $CURSOR
  PROMPT=$_probe_saved_prompt
  RPROMPT=$_probe_saved_rprompt
  _probe_collapsed=0
  _probe_redraw_from_anchor $REPLY
}

_probe_restart_timer() {
  emulate -L zsh

  if (( _probe_timer_fd >= 0 )); then
    zle -F $_probe_timer_fd 2>/dev/null
    exec {_probe_timer_fd}<&-
  fi
  exec {_probe_timer_fd}< <(command sleep 0.3)
  zle -F $_probe_timer_fd _probe_settle
}

TRAPWINCH() {
  emulate -L zsh
  [[ $_probe_mode == (auto|collapse) ]] && zle 2>/dev/null || return 0

  if [[ $_probe_mode == auto ]]; then
    _probe_fix_anchor
    _probe_rows_above "$PROMPT" $COLUMNS $CURSOR
    _probe_redraw_from_anchor $REPLY
    return 0
  fi

  if (( ! _probe_collapsed )); then
    _probe_fix_anchor
    _probe_rows_above "$PROMPT" $COLUMNS $CURSOR
    _probe_saved_prompt=$PROMPT
    _probe_saved_rprompt=$RPROMPT
    PROMPT='%# '
    RPROMPT=''
    _probe_collapsed=1
    _probe_redraw_from_anchor $REPLY
  fi
  _probe_restart_timer
}

autoload -Uz add-zsh-hook
add-zsh-hook precmd _probe_anchor_mark
zle -N _probe_anchor_widget
bindkey '^G' _probe_anchor_widget
