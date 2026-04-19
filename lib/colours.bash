#!/usr/bin/env bash
# =============================================================================
# lib/colours.bash -- ANSI colour definitions and palette viewer
# =============================================================================
#
# What this module does:
#   Defines two associative arrays that map colour names to ANSI escape
#   sequences.  These arrays are used throughout the bash configuration
#   (primarily by lib/logging.bash and the _printf helper) to produce
#   coloured terminal output.
#
#   Also provides the `colours` function for interactive palette viewing.
#
# Dependencies:
#   None -- this is the lowest-level library file.
#
# Exports (global variables):
#   __ansi_colours   Indexed array mapping 0-7 to colour names
#   __colours        Associative array mapping colour names to escape codes
#
# Exports (functions):
#   colours           Display the terminal colour palette
#
# =============================================================================

# ---------------------------------------------------------------------------
# Indexed array: ANSI colour number -> colour name
# Used by the `colours` viewer to iterate the basic 8-colour palette.
# ---------------------------------------------------------------------------

declare -A __ansi_colours=(
  [0]='black'
  [1]='red'
  [2]='green'
  [3]='yellow'
  [4]='blue'
  [5]='magenta'
  [6]='cyan'
  [7]='white'
)

# ---------------------------------------------------------------------------
# Associative array: colour name -> ANSI escape sequence
#
# Each of the eight basic colours has three variants:
#   name        Normal weight  (e.g. "red")
#   boldNAME    Bold / bright  (e.g. "boldred")
#   dimNAME     Dim / faint    (e.g. "dimred")
#
# The special key "default" resets all attributes.
# ---------------------------------------------------------------------------

declare -A __colours=(
  ['default']='\033[0m'

  ['black']='\033[0;30m'      ['boldblack']='\033[1;30m'      ['dimblack']='\033[2;30m'
  ['red']='\033[0;31m'        ['boldred']='\033[1;31m'        ['dimred']='\033[2;31m'
  ['green']='\033[0;32m'      ['boldgreen']='\033[1;32m'      ['dimgreen']='\033[2;32m'
  ['yellow']='\033[0;33m'     ['boldyellow']='\033[1;33m'     ['dimyellow']='\033[2;33m'
  ['blue']='\033[0;34m'       ['boldblue']='\033[1;34m'       ['dimblue']='\033[2;34m'
  ['magenta']='\033[0;35m'    ['boldmagenta']='\033[1;35m'    ['dimmagenta']='\033[2;35m'
  ['cyan']='\033[0;36m'       ['boldcyan']='\033[1;36m'       ['dimcyan']='\033[2;36m'
  ['white']='\033[0;37m'      ['boldwhite']='\033[1;37m'      ['dimwhite']='\033[2;37m'
)

# ---------------------------------------------------------------------------
# colours -- Display the terminal colour palette
#
# Usage:
#   colours           Show the 8 basic ANSI colours in normal, bold, and dim
#   colours -v        Show the full 256-colour extended palette
# ---------------------------------------------------------------------------

colours() {
  local _params=("$@")

  if (( ${#_params[@]} == 0 )); then
    # -- Basic 8-colour palette with normal / bold / dim variants -----------
    for i in {0..7}; do
      local _col="${__ansi_colours[$i]}"
      local _boldcol="bold${_col}"
      local _dimcol="dim${_col}"

      # shellcheck disable=SC2059
      printf "${__colours[${_col}]}  %-9s${__colours[default]}" "${_col}"
      # shellcheck disable=SC2059
      printf "${__colours[${_boldcol}]}  %-13s${__colours[default]}" "${_boldcol}"
      # shellcheck disable=SC2059
      printf "${__colours[${_dimcol}]}  %-12s${__colours[default]}\n" "${_dimcol}"
    done

  elif (( ${#_params[@]} == 1 )); then
    # -- Extended 256-colour palette ----------------------------------------
    for i in {0..255}; do
      printf "\x1b[38;5;%smcolour%-4s\x1b[0m" "${i}" "${i}"
      # Print 8 colours per line for readability
      (( (i + 1) % 8 == 0 )) && printf "\n"
    done

  else
    printf "usage: colours [-v]\n"
  fi
}
