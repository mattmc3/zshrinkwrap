# Probe: does printing the upper prompt lines outside zle make resize race-free?
# Usage: start `zsh -f`, then: source test/probe/split.zsh [oneline|twoline|tworight] [cursor|decsc]
# precmd prints every prompt line but the last, so zle only draws one line.
# Once resizing settles, the upper lines are cleared and reprinted at the new
# width, measured up from the input line. `cursor` finds the input line from
# the cursor row, which the collapsed prompt keeps on it while resizing. `decsc` finds
# it from a cursor saved at precmd.

source ${${(%):-%x}:A:h}/common.zsh

probe_layout ${1:-oneline} || return 1
typeset -g _probe_anchor=${2:-cursor}
[[ $_probe_anchor == (cursor|decsc) ]] || {
  print -u2 -r -- "unknown anchor '$_probe_anchor' (want cursor|decsc)"
  return 1
}
probe_env
print -r -- "layout=${1:-oneline} mode=split anchor=$_probe_anchor; resize freely"

typeset -g _probe_full_prompt _probe_zle_prompt _probe_upper_prompt
typeset -ga _probe_upper=()
typeset -gi _probe_timer_fd=-1 _probe_collapsed=0 _probe_pushed=0 _probe_saved_cursor=0
typeset -g _probe_saved_rprompt

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

# Rows the recorded upper prompt lines take at `cols` wide.
_probe_upper_rows() {
  emulate -L zsh
  local -i cols=$1 rows=0 len

  for len in $_probe_upper; do
    (( rows += len > 0 ? (len + cols - 1) / cols : 1 ))
  done
  typeset -g REPLY=$rows
}

# Print the upper prompt lines, record their widths, and save the cursor at the
# start of the line zle will draw.
_probe_print_upper() {
  emulate -L zsh -o extendedglob
  local line
  local -a lines

  _probe_upper=()
  [[ -n $_probe_upper_prompt ]] || { print -rn -- $'\e7'; return 0 }
  lines=( "${(@f)${(%%)_probe_upper_prompt}}" )
  for line in $lines; do
    print -r -- $line
    line=${line//$'\e'\[[0-9;]#m/}
    _probe_upper+=( ${(m)#line} )
  done
  print -rn -- $'\e7'
}

_probe_cancel_timer() {
  emulate -L zsh

  if (( _probe_timer_fd >= 0 )); then
    zle -F $_probe_timer_fd 2>/dev/null
    exec {_probe_timer_fd}<&-
    _probe_timer_fd=-1
  fi
}

_probe_split_precmd() {
  emulate -L zsh
  _probe_cancel_timer
  # Accepting a line mid-resize: zsh pops the stashed buffer by itself.
  if (( _probe_collapsed )); then
    PROMPT=$_probe_zle_prompt
    RPROMPT=$_probe_saved_rprompt
    _probe_collapsed=0
    _probe_pushed=0
  fi
  # A theme that rebuilt PROMPT since last time wins over our saved copy.
  [[ $PROMPT == $_probe_zle_prompt ]] || _probe_full_prompt=$PROMPT
  if [[ $_probe_full_prompt == *$'\n'* ]]; then
    _probe_upper_prompt=${_probe_full_prompt%$'\n'*}
    _probe_zle_prompt=${_probe_full_prompt##*$'\n'}
  else
    _probe_upper_prompt=
    _probe_zle_prompt=$_probe_full_prompt
  fi
  PROMPT=$_probe_zle_prompt
  _probe_print_upper
}

_probe_settle() {
  emulate -L zsh
  local fd=$1

  zle -F $fd 2>/dev/null
  exec {fd}<&-
  (( fd == _probe_timer_fd )) || return 0
  _probe_timer_fd=-1

  _probe_rows_above "$PROMPT" $COLUMNS 0
  local -i park=$REPLY
  PROMPT=$_probe_zle_prompt
  RPROMPT=$_probe_saved_rprompt
  _probe_collapsed=0
  if (( _probe_pushed )); then
    zle get-line
    (( CURSOR = _probe_saved_cursor < $#BUFFER ? _probe_saved_cursor : $#BUFFER ))
    _probe_pushed=0
  fi

  _probe_upper_rows $COLUMNS
  [[ $_probe_anchor == decsc ]] && print -rn -- $'\e8'
  (( REPLY > 0 )) && print -rn -- $'\e['$REPLY'A'
  print -rn -- $'\r\e[0J'
  _probe_print_upper
  (( park > 0 )) && print -rn -- ${(pl:park::\n:)}
  zle reset-prompt
}

# Collapse the input line to a short prompt with the command stashed, so no
# redraw during the resize can wrap it.
TRAPWINCH() {
  emulate -L zsh
  zle 2>/dev/null || return 0

  if (( ! _probe_collapsed )); then
    _probe_saved_rprompt=$RPROMPT
    _probe_saved_cursor=$CURSOR
    if [[ -n $BUFFER ]]; then
      zle push-line && _probe_pushed=1
    fi
    PROMPT='%# '
    RPROMPT=''
    _probe_collapsed=1
    zle reset-prompt
  fi

  _probe_cancel_timer
  exec {_probe_timer_fd}< <(command sleep 0.3)
  zle -F $_probe_timer_fd _probe_settle
}

autoload -Uz add-zsh-hook
add-zsh-hook precmd _probe_split_precmd
