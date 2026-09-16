#!/usr/bin/env zsh
# Probe: does the terminal move the saved cursor (DECSC) along with reflowed text?
# Usage: zsh test/probe/decsc.zsh [long|short|cursor]
# `short` keeps the anchor line itself from wrapping when the window shrinks.
# `cursor` leaves the cursor on the long anchor line, like a right prompt.

emulate -L zsh
source ${0:A:h}/common.zsh

local -i cols=${$(stty size </dev/tty)[2]}
local -i w=$(( cols - 1 ))
local above=${(r:w::=:)${:-"above "}}
local mode=${1:-long}
local anchor="A> anchor"
[[ $mode == short ]] || anchor=${(r:w::-:)anchor}

print -rn -- $'\e[H\e[2J'
print -r -- "1. Shrink the window by about 20 columns, then press Enter."
print -r -- "2. Widen it back, then press Enter."
print -r -- "Then report where [1] and [2] landed:"
print -r -- "  on the 'A> anchor' line = saved cursor follows reflow"
print -r -- "  anywhere else           = it does not"
print
probe_env
print -r -- $above
print -rn -- $'\e7'
if [[ $mode == cursor ]]; then
  print -rn -- $anchor$'\r\e[3C'
else
  print -r -- $anchor
  print -r -- "B> below anchor"
fi
read -rs </dev/tty
print -rn -- $'\e8\e[7m[1]\e[0m'
read -rs </dev/tty
print -rn -- $'\e8\e[4C\e[7m[2]\e[0m'
print -rn -- $'\e[999B\r\n'
