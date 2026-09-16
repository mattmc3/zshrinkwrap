# Shared helpers for the resize probes.

probe_env() {
  local size
  size=$(stty size </dev/tty 2>/dev/null)
  print -r -- "terminal: ${TERM_PROGRAM:-unknown} ${TERM_PROGRAM_VERSION:-}"
  print -r -- "TERM=$TERM zsh=$ZSH_VERSION size=${size#* }x${size% *}"
}

# Set PROMPT and RPROMPT to a named layout.
#   oneline: short left prompt plus a right prompt
#   twoline: full-width first line (the p10k repro), then "> "
#   tworight: twoline plus a right prompt on the input line
probe_layout() {
  case $1 in
    oneline)
      PROMPT='%F{blue}%~%f %# '
      RPROMPT='%F{cyan}[right prompt %D{%H:%M:%S}]%f'
      ;;
    twoline)
      setopt prompt_subst
      PROMPT=$'left>${(pl.$((COLUMNS-12))..-.)}<right\n> '
      RPROMPT=''
      ;;
    tworight)
      probe_layout twoline
      RPROMPT='%F{cyan}[right prompt %D{%H:%M:%S}]%f'
      ;;
    *)
      print -u2 -r -- "unknown layout '$1' (want oneline|twoline|tworight)"
      return 1
      ;;
  esac
}
