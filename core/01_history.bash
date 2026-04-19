#!/usr/bin/env bash
# =============================================================================
# core/01_history.bash -- Shell history configuration
# =============================================================================
#
# What this module does:
#   Configures bash history behaviour: where the history file is stored,
#   how large it can grow, what gets ignored, and how multiple terminal
#   sessions merge their histories.
#
# Dependencies:
#   XDG_CACHE_HOME   (from ~/.bash_profile)
#   _status_set      (from lib/logging.bash)
#
# Exports (environment variables):
#   HISTCONTROL      What to exclude from history (dupes + leading spaces)
#   HISTTIMEFORMAT   Timestamp format for `history` output
#   HISTIGNORE       Patterns for commands to never record
#   HISTFILE         Path to the history file (XDG-compliant)
#   HISTFILESIZE     Max lines in the history file on disk
#   HISTSIZE         Max entries held in memory
#
# Shell options:
#   histappend       Append to history file instead of overwriting on exit
#   cdable_vars      Allow `cd varname` when varname holds a directory path
#
# =============================================================================

# ---------------------------------------------------------------------------
# History controls
# ---------------------------------------------------------------------------

# "ignoreboth" combines "ignorespace" (lines starting with a space are not
# recorded) and "ignoredups" (consecutive duplicate lines are collapsed).
export HISTCONTROL="ignoreboth"

# Prefix each history entry with a timestamp when displayed via `history`.
export HISTTIMEFORMAT='[%Y-%m-%d %T] '

# Commands that are too trivial or transient to clutter history.
export HISTIGNORE="ls -latr:ls:exit:bg:fg:history"

# ---------------------------------------------------------------------------
# History file location (XDG-compliant)
# ---------------------------------------------------------------------------

# Ensure the cache directory exists before bash tries to write to it.
if [[ ! -d "${XDG_CACHE_HOME}/bash" ]]; then
  mkdir -p "${XDG_CACHE_HOME}/bash"
fi

export HISTFILE="${XDG_CACHE_HOME}/bash/bash_history"

# ---------------------------------------------------------------------------
# History size
# ---------------------------------------------------------------------------

# HISTFILESIZE: max lines stored in the on-disk history file.
# HISTSIZE:     max entries held in the in-memory history list.
# Both are set generously -- disk is cheap, and searchable history is valuable.
export HISTFILESIZE=1000000
export HISTSIZE=100000

# ---------------------------------------------------------------------------
# Shell options related to history and navigation
# ---------------------------------------------------------------------------

# histappend: When the shell exits, APPEND history to HISTFILE instead of
# overwriting it.  Essential when running multiple terminal windows so they
# don't clobber each other's history.
shopt -s histappend

# cdable_vars: Treat unrecognised `cd` arguments as variable names.
# This lets you do things like:
#   docs="$HOME/Documents/projects"
#   cd docs                              # jumps to $HOME/Documents/projects
# Note: you don't need the $ prefix, and it works from any directory.
shopt -s cdable_vars

# ---------------------------------------------------------------------------
# Status report
# ---------------------------------------------------------------------------

_status_set "history" "ok" "append, $(_sc 75)${HISTSIZE}$(_sr) entries"
