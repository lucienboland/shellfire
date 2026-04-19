#!/usr/bin/env bash
# =============================================================================
# core/03_environment.bash -- General environment variables and shell options
# =============================================================================
#
# What this module does:
#   Sets environment variables that control the behaviour of the shell and
#   common command-line tools.  This is the "personality" of the shell --
#   colours, editor, prompt behaviour, and macOS-specific workarounds.
#
# Dependencies:
#   _status_set   (from lib/logging.bash)
#
# Exports (environment variables):
#   CLICOLOR                        Enable coloured output for BSD ls
#   LSCOLORS                        Colour scheme for BSD ls
#   COMMAND_MODE                    macOS command compatibility mode
#   BASH_SILENCE_DEPRECATION_WARNING  Suppress macOS zsh-migration nag
#   PROMPT_DIRTRIM                  Truncate prompt path to N directories
#   EDITOR                          Preferred text editor
#   GREP_OPTIONS                    Default grep options (interactive only)
#   LESSHISTFILE                    Disable less history file
#
# =============================================================================

# ---------------------------------------------------------------------------
# Terminal colours for ls (BSD/macOS variant)
# ---------------------------------------------------------------------------

# CLICOLOR: When set, BSD ls uses colour output.
export CLICOLOR=1

# LSCOLORS: Defines the colour scheme for BSD ls.
# This is a 22-character string where pairs of characters set foreground and
# background colours for different file types.  The order is:
#   directory, symlink, socket, pipe, executable, block-special,
#   char-special, setuid, setgid, sticky-dir, non-sticky-dir
#
# See: man ls (search for LSCOLORS) for the full mapping.
export LSCOLORS=ExFxCxDxBxegedabagacad

# ---------------------------------------------------------------------------
# macOS-specific settings
# ---------------------------------------------------------------------------

# COMMAND_MODE: Controls whether macOS command-line tools use POSIX-2003
# or legacy behaviour.  "unix2003" is the modern default.
export COMMAND_MODE=unix2003

# Suppress the "default interactive shell is now zsh" warning that macOS
# prints on every new bash login shell since Catalina.
export BASH_SILENCE_DEPRECATION_WARNING=1

# ---------------------------------------------------------------------------
# Prompt
# ---------------------------------------------------------------------------

# PROMPT_DIRTRIM: When set, bash truncates the \w and \W prompt escapes
# to show only the last N directory components, prefixed with "~" or "...".
# This keeps the prompt readable even in deeply nested directories.
export PROMPT_DIRTRIM=3

# ---------------------------------------------------------------------------
# Editor
# ---------------------------------------------------------------------------

# Prefer neovim if it's installed; otherwise leave EDITOR unset (or whatever
# the system default is).
_sf_editor_detail="none"
if command -v nvim &>/dev/null; then
  EDITOR="$(command -v nvim)"
  export EDITOR
  _sf_editor_detail="nvim"
fi

# ---------------------------------------------------------------------------
# Grep
# ---------------------------------------------------------------------------

# Enable coloured grep output, but ONLY in interactive sessions.
# Setting GREP_OPTIONS in non-interactive shells can break scripts that
# parse grep output.
if [[ -t 0 ]]; then
  export GREP_OPTIONS="--colour=auto"
fi

# ---------------------------------------------------------------------------
# Less
# ---------------------------------------------------------------------------

# Disable the less history file.  The "-" value is a less convention meaning
# "do not write a history file".
export LESSHISTFILE="-"

# ---------------------------------------------------------------------------
# Status report
# ---------------------------------------------------------------------------

_status_set "environment" "ok" "editor: $(_sc 114)${_sf_editor_detail}$(_sr)"
unset _sf_editor_detail
