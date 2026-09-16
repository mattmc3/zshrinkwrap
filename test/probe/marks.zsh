# Probe: does the terminal clear a marked prompt on resize so zsh can redraw it?
# Usage: start `zsh -f`, then: source test/probe/marks.zsh [133|633|none] [oneline|twoline]
# Resize back and forth a few times at the prompt, with and without a long
# command typed, and note whether stale prompt lines pile up.

source ${${(%):-%x}:A:h}/common.zsh

() {
  local kind=${1:-133}
  case $kind in
    133|633) ;;
    none) ;;
    *) print -u2 -r -- "unknown marks '$kind' (want 133|633|none)"; return 1 ;;
  esac
  probe_layout ${2:-oneline} || return 1

  typeset -g _probe_marks=$kind
  if [[ $kind != none ]]; then
    PROMPT="%{"$'\e]'"$kind;A"$'\a'"%}$PROMPT%{"$'\e]'"$kind;B"$'\a'"%}"
  fi

  probe_env
  print -r -- "marks=$kind layout=${2:-oneline}"
  print -r -- "Resize back and forth several times at the prompt, then report:"
  print -r -- "  clean     = one prompt, no stale 'left>---' or prompt copies above it"
  print -r -- "  staircase = leftover prompt fragments"
  print -r -- "Repeat with a long command typed but not run."
} "$@" || return 1

_probe_marks_preexec() {
  [[ $_probe_marks == none ]] || print -rn -- $'\e]'"$_probe_marks;C"$'\a'
}

_probe_marks_precmd() {
  local -i st=$?
  [[ $_probe_marks == none ]] || print -rn -- $'\e]'"$_probe_marks;D;$st"$'\a'
}

autoload -Uz add-zsh-hook
add-zsh-hook preexec _probe_marks_preexec
add-zsh-hook precmd _probe_marks_precmd
