# Mitigate prompt damage when a terminal reflows text during a resize.

if (( ${_zshrinkwrap_loaded:-0} )); then
  _zshrinkwrap_cancel_timer
  _zshrinkwrap_restore
  _zshrinkwrap_split_preexec
  if (( $+functions[_zshrinkwrap_previous_trapwinch] )); then
    functions[TRAPWINCH]=$functions[_zshrinkwrap_previous_trapwinch]
    unfunction _zshrinkwrap_previous_trapwinch
  else
    unfunction TRAPWINCH 2>/dev/null
  fi
fi
typeset -gi _zshrinkwrap_loaded=1

zmodload zsh/datetime

typeset -gi _zshrinkwrap_active=0
typeset -gi _zshrinkwrap_pushed=0
typeset -gi _zshrinkwrap_timer_fd=-1
typeset -gi _zshrinkwrap_last_cols=${COLUMNS:-80}
typeset -gi _zshrinkwrap_saved_cursor=0
typeset -gF _zshrinkwrap_deadline=0.0
typeset -g _zshrinkwrap_saved_prompt
typeset -g _zshrinkwrap_saved_rprompt
typeset -g _zshrinkwrap_split_orig
typeset -g _zshrinkwrap_split_set
typeset -g _zshrinkwrap_split_line
typeset -g _zshrinkwrap_rprompt_orig
typeset -g _zshrinkwrap_rprompt_set
typeset -ga _zshrinkwrap_upper_widths=()
typeset -ga _zshrinkwrap_saved_highlight=()

if (( $+functions[TRAPWINCH] && ! $+functions[_zshrinkwrap_previous_trapwinch] )); then
  functions[_zshrinkwrap_previous_trapwinch]=$functions[TRAPWINCH]
fi

typeset -gA _zshrinkwrap_defaults=(
  symbol        '%F{magenta}%#%f '
  restore-delay '0.20'
)

# An empty style counts as unset, so a blank value cannot leave the
# prompt or the sleep interval with nothing usable.
_zshrinkwrap_style() {
  emulate -L zsh
  local value

  zstyle -s ':zshrinkwrap:resize' $1 value
  [[ -n $value ]] || value=${_zshrinkwrap_defaults[$1]}
  typeset -g REPLY=$value
}

# Pick how to handle a resize: `none` when the terminal cleans up the prompt
# itself, `split` where the split prompt redraw is verified, `estimate`
# otherwise.
_zshrinkwrap_strategy() {
  emulate -L zsh
  local value

  if zstyle -s ':zshrinkwrap:resize' strategy value && [[ -n $value ]]; then
    typeset -g REPLY=$value
    return 0
  fi

  case $TERM_PROGRAM in
    vscode|Apple_Terminal) value=split ;;
    # Ghostty clears prompts marked with OSC 133, which its integration adds.
    ghostty)
      if (( $+functions[_ghostty_precmd] || $+functions[_ghostty_deferred_init] )); then
        value=none
      else
        value=estimate
      fi
      ;;
    *) value=estimate ;;
  esac
  typeset -g REPLY=$value
}

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
    # Highlighters may not rerun for a line restored from a timer.
    region_highlight=( "${_zshrinkwrap_saved_highlight[@]}" )
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

  _zshrinkwrap_strategy
  local strategy=$REPLY
  if [[ $strategy == estimate ]] && zstyle -T ':zshrinkwrap:resize' reflow; then
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

    # Split needs a short input line so no redraw while resizing can wrap.
    if [[ $strategy == split ]] || zstyle -t ':zshrinkwrap:resize' shrink-lprompt; then
      if [[ -n $BUFFER ]]; then
        _zshrinkwrap_saved_highlight=( "${region_highlight[@]}" )
        zle push-line && _zshrinkwrap_pushed=1
      fi
      _zshrinkwrap_style symbol
      PROMPT=$REPLY
    fi
    if [[ $strategy == split ]] || zstyle -T ':zshrinkwrap:resize' shrink-rprompt; then
      RPROMPT=''
    fi
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
  _zshrinkwrap_strategy
  if [[ $REPLY == split ]]; then
    _zshrinkwrap_split_redraw
  else
    _zshrinkwrap_restore
    zle reset-prompt
  fi
}

_zshrinkwrap_start_timer() {
  emulate -L zsh
  local delay=$1

  if [[ -z $delay ]]; then
    _zshrinkwrap_style restore-delay
    delay=$REPLY
  fi

  (( _zshrinkwrap_timer_fd >= 0 )) && return 0
  exec {_zshrinkwrap_timer_fd}< <(command sleep "$delay")
  # As a widget the handler sees live zle state, such as region_highlight.
  zle -F -w $_zshrinkwrap_timer_fd _zshrinkwrap_timer_ready
}

TRAPWINCH() {
  emulate -L zsh
  local trap_status=0
  local restore_delay

  if (( $+functions[_zshrinkwrap_previous_trapwinch] )); then
    _zshrinkwrap_previous_trapwinch || trap_status=$?
  fi

  _zshrinkwrap_strategy
  if [[ $REPLY != none ]] && zle 2>/dev/null; then
    _zshrinkwrap_adjust
    _zshrinkwrap_style restore-delay
    restore_delay=$REPLY
    (( _zshrinkwrap_deadline = EPOCHREALTIME + restore_delay ))
    _zshrinkwrap_start_timer $restore_delay
  fi

  _zshrinkwrap_last_cols=${COLUMNS:-80}
  return $trap_status
}

# Split strategy. Zle only draws the last prompt line; the lines above it are
# printed at precmd like command output, so resizing reflows them as history
# instead of leaving zle to redraw them from a stale row offset.

# Width of a line once escape sequences are removed.
_zshrinkwrap_display_width() {
  emulate -L zsh -o extendedglob
  local line=$1

  line=${line//$'\e'\[[0-?]#[ -\/]#[@-~]/}
  line=${line//$'\e'\][^$'\a'$'\e']#($'\a'|$'\e'\\)/}
  typeset -g REPLY=${(m)#line}
}

# Print every prompt line but the last and hand zle the last one.
_zshrinkwrap_split_print() {
  local full=$_zshrinkwrap_split_orig
  [[ -o prompt_subst ]] && full=${(e)full}

  emulate -L zsh
  local line
  _zshrinkwrap_upper_widths=()
  _zshrinkwrap_split_set=
  if [[ $full != *$'\n'* ]]; then
    PROMPT=$_zshrinkwrap_split_orig
    return 0
  fi

  for line in "${(@f)${(%)full%$'\n'*}}"; do
    print -r -- $line
    _zshrinkwrap_display_width $line
    _zshrinkwrap_upper_widths+=( $REPLY )
  done

  # The last line is already evaluated, so keep prompt_subst from running it
  # again by expanding it through a parameter.
  _zshrinkwrap_split_line=${full##*$'\n'}
  if [[ -o prompt_subst ]]; then
    _zshrinkwrap_split_set='${_zshrinkwrap_split_line}'
  else
    _zshrinkwrap_split_set=$_zshrinkwrap_split_line
  fi
  PROMPT=$_zshrinkwrap_split_set
}

_zshrinkwrap_split_precmd() {
  local subst=${options[prompt_subst]}
  emulate -L zsh
  [[ $subst == on ]] && setopt prompt_subst
  _zshrinkwrap_strategy
  [[ $REPLY == split ]] || return 0

  # A theme that rebuilt a prompt since last time wins over the saved copy.
  if [[ -z $_zshrinkwrap_split_set || $PROMPT != $_zshrinkwrap_split_set ]]; then
    _zshrinkwrap_split_orig=$PROMPT
  fi
  if [[ -z $_zshrinkwrap_rprompt_set || $RPROMPT != $_zshrinkwrap_rprompt_set ]]; then
    _zshrinkwrap_rprompt_orig=$RPROMPT
  fi

  # Zsh reaches the right prompt with a cursor move that stops at the edge,
  # but its text autowraps if the terminal already shrank, dropping the
  # cursor a row. With autowrap off it overwrites the last column instead.
  _zshrinkwrap_rprompt_set=
  if [[ -n $_zshrinkwrap_rprompt_orig ]]; then
    _zshrinkwrap_rprompt_set=$'%{\e[?7l%}'$_zshrinkwrap_rprompt_orig$'%{\e[?7h%}'
    RPROMPT=$_zshrinkwrap_rprompt_set
  fi
  _zshrinkwrap_split_print
}

# Give other hooks and the running command the prompt the theme set.
_zshrinkwrap_split_preexec() {
  if [[ -n $_zshrinkwrap_split_set && $PROMPT == $_zshrinkwrap_split_set ]]; then
    PROMPT=$_zshrinkwrap_split_orig
  fi
  if [[ -n $_zshrinkwrap_rprompt_set && $RPROMPT == $_zshrinkwrap_rprompt_set ]]; then
    RPROMPT=$_zshrinkwrap_rprompt_orig
  fi
  return 0
}

# Once resizing settles, the collapsed input line sits on the cursor row. Climb
# the upper lines as they wrap at the final width, clear, and draw it all again.
_zshrinkwrap_split_redraw() {
  local subst=${options[prompt_subst]}
  emulate -L zsh
  [[ $subst == on ]] && setopt prompt_subst
  local -i rows=0 len park

  _zshrinkwrap_rows_above "$PROMPT" ${COLUMNS:-80} 0
  park=$REPLY
  _zshrinkwrap_restore
  for len in $_zshrinkwrap_upper_widths; do
    (( rows += len > 0 ? (len + COLUMNS - 1) / COLUMNS : 1 ))
  done
  (( rows > 0 )) && print -rn -- $'\e['$rows'A'
  print -rn -- $'\r\e[0J'
  [[ $PROMPT == $_zshrinkwrap_split_set ]] && _zshrinkwrap_split_print
  (( park > 0 )) && print -rn -- ${(pl:park::\n:)}
  zle reset-prompt
}

autoload -Uz add-zsh-hook
zle -N _zshrinkwrap_timer_ready
add-zsh-hook precmd _zshrinkwrap_restore
add-zsh-hook precmd _zshrinkwrap_split_precmd
add-zsh-hook preexec _zshrinkwrap_split_preexec
# https://github.com/romkatv/powerlevel10k#horrific-mess-when-resizing-terminal-window
