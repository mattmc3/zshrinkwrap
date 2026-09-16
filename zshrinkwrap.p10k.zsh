# powerlevel10k support for the split strategy. Sourced by
# zshrinkwrap.plugin.zsh when p10k is detected.

typeset -gi _zshrinkwrap_p10k_hidden=0
typeset -gi _zshrinkwrap_p10k_pending=0
typeset -g _zshrinkwrap_p10k_printed

# powerlevel10k builds PROMPT as ${_p9k__1-<line 1>}${_p9k__2-<line 2>}, keeps
# its precmd hook last, and redraws through `zle .reset-prompt` for async
# segments and the transient prompt. So instead of replacing PROMPT, split
# prints the upper lines and hides them in p10k's template by setting
# _p9k__<n> empty, leaving PROMPT live. Wrappers around p10k's functions
# repaint printed lines on async updates and erase them for transient prompts.
_zshrinkwrap_p10k_install() {
  emulate -L zsh
  local fn
  local -A wrappers=(
    _p9k_precmd                     _zshrinkwrap_p10k_after_precmd
    _p9k_reset_prompt               _zshrinkwrap_p10k_after_reset
    _p9k_on_widget_zle-line-finish  _zshrinkwrap_p10k_line_finish
  )
  for fn in ${(k)wrappers}; do
    (( $+functions[$fn] )) || continue
    # p10k reload redefines its functions, so check the body, not a flag.
    [[ $functions[$fn] == *_zshrinkwrap_p10k_* ]] && continue
    functions[_zshrinkwrap_p10k_orig_$fn]=$functions[$fn]
    if [[ $fn == _p9k_on_widget_zle-line-finish ]]; then
      functions[$fn]="$wrappers[$fn] \"\$@\""
    else
      functions[$fn]="_zshrinkwrap_p10k_orig_$fn \"\$@\"; local -i st=\$?; $wrappers[$fn]; return st"
    fi
  done
}

# Lines p10k draws above the input line.
_zshrinkwrap_p10k_upper_count() {
  local -i count=$(( ${#_p9k_line_segments_left} - 1 ))
  typeset -g REPLY=$(( count > 0 ? count : 0 ))
}

_zshrinkwrap_p10k_show() {
  (( _zshrinkwrap_p10k_hidden )) || return 0
  local -i i
  _zshrinkwrap_p10k_upper_count
  for (( i = 1; i <= REPLY; i++ )); do
    unset _p9k__$i
  done
  _zshrinkwrap_p10k_hidden=0
}

# Expand p10k's upper lines as zle would draw them right now.
_zshrinkwrap_p10k_upper_text() {
  setopt local_options no_sh_glob no_ksh_glob
  local full
  _zshrinkwrap_p10k_show
  full=${(%%)PROMPT}
  # p10k starts line 1 with a newline and a cursor up (\e[A, or \eM from some
  # terminfo), which nets no row.
  full=${full//$'\n\e['(1|)A/}
  full=${full//$'\n\eM'/}
  if [[ $full == *$'\n'* ]]; then
    typeset -g REPLY=${full%$'\n'*}
  else
    typeset -g REPLY=
  fi
}

_zshrinkwrap_p10k_hide() {
  local -i i
  _zshrinkwrap_p10k_upper_count
  for (( i = 1; i <= REPLY; i++ )); do
    typeset -g _p9k__$i=
  done
  _zshrinkwrap_p10k_hidden=1
}

_zshrinkwrap_p10k_print() {
  local line upper
  _zshrinkwrap_upper_widths=()
  _zshrinkwrap_p10k_upper_text
  upper=$REPLY
  [[ -n $upper ]] || return 0
  for line in "${(@f)upper}"; do
    print -r -- $line
    _zshrinkwrap_display_width $line
    _zshrinkwrap_upper_widths+=( $REPLY )
  done
  typeset -g _zshrinkwrap_p10k_printed=$upper
  _zshrinkwrap_p10k_hide
}

_zshrinkwrap_p10k_after_precmd() {
  _zshrinkwrap_strategy
  [[ $REPLY == split ]] || return 0
  _zshrinkwrap_p10k_upper_count
  (( REPLY > 0 )) || return 0
  # A line the user hid with `p10k display` stays hidden.
  (( $+_p9k__1 && ! _zshrinkwrap_p10k_hidden )) && return 0
  _zshrinkwrap_wrap_rprompt
  _zshrinkwrap_p10k_print
  # p10k finishes some segments on its first expansion under zle, so check
  # the printed lines again once zle starts.
  _zshrinkwrap_p10k_pending=1
}

_zshrinkwrap_p10k_line_init() {
  (( _zshrinkwrap_p10k_pending )) || return 0
  _zshrinkwrap_p10k_pending=0
  _zshrinkwrap_p10k_repaint
}

# Rows of printed upper lines at the current width, and rows of the input
# line above the cursor for the given prompt.
_zshrinkwrap_p10k_rows() {
  local prompt=$1
  local -i len upper=0 above=0
  for len in $_zshrinkwrap_upper_widths; do
    (( upper += len > 0 ? (len + COLUMNS - 1) / COLUMNS : 1 ))
  done
  _zshrinkwrap_display_width ${${(%%)prompt}##*$'\n'}
  (( above = (REPLY + ${CURSOR:-0}) / COLUMNS ))
  typeset -ga reply=( $upper $above )
}

# An async segment changed: repaint the printed upper lines in place.
_zshrinkwrap_p10k_after_reset() {
  (( ! $+_p9k__line_finished )) && zle 2>/dev/null || return 0
  _zshrinkwrap_p10k_repaint
}

# Only the one-line hidden prompt is ever drawn by zle, so the cursor is on the
# input line and the printed upper lines sit directly above it.
_zshrinkwrap_p10k_repaint() {
  (( _zshrinkwrap_p10k_hidden && ! _zshrinkwrap_active )) || return 0
  local old=$_zshrinkwrap_p10k_printed new line
  local -a widths=( $_zshrinkwrap_upper_widths )
  _zshrinkwrap_p10k_upper_text
  new=$REPLY
  _zshrinkwrap_p10k_hide
  [[ $new == $old ]] && return 0
  (( ${#${(@f)new}} == $#widths )) || return 0
  _zshrinkwrap_p10k_rows $PROMPT
  local -i up=$(( reply[1] + reply[2] ))
  (( up > 0 && up < LINES )) || return 0
  print -rn -- $'\e7\e['$up$'A\r'
  for line in "${(@f)new}"; do
    print -rn -- $'\e[K'$line$'\r\n'
  done
  print -rn -- $'\e8'
  typeset -g _zshrinkwrap_p10k_printed=$new
}

# The transient prompt redraws only the input line; delete the printed upper
# lines above it and move the cursor up with the content.
_zshrinkwrap_p10k_line_finish() {
  local -i erase=0
  if (( _zshrinkwrap_p10k_hidden && ! $+_p9k__line_finished )) &&
     [[ -n $_p9k_transient_prompt ]] &&
     [[ $_POWERLEVEL9K_TRANSIENT_PROMPT == always || $_p9k__cwd == $_p9k__last_prompt_pwd ]]; then
    erase=1
  fi
  _zshrinkwrap_p10k_orig__p9k_on_widget_zle-line-finish "$@"
  local -i st=$?
  if (( erase )); then
    _zshrinkwrap_p10k_rows $_p9k_transient_prompt
    local -i n=$reply[1] up=$(( reply[1] + reply[2] ))
    if (( n > 0 && up < LINES )); then
      print -rn -- $'\e7\e['$up$'A\r\e['$n$'M\e8\e['$n'A'
    fi
    _zshrinkwrap_upper_widths=()
  fi
  return st
}

autoload -Uz add-zle-hook-widget
add-zle-hook-widget line-init _zshrinkwrap_p10k_line_init
