#!/usr/bin/env bash
# =============================================================================
# core/04_completions.bash -- Bash tab-completion setup
# =============================================================================
#
# What this module does:
#   Loads the Homebrew-managed bash completion framework, which provides
#   tab completion for git, docker, kubectl, and hundreds of other tools.
#
# Dependencies:
#   __homebrew_dir   (from core/02_path.bash)
#   _status_set      (from lib/logging.bash)
#
# =============================================================================

# ---------------------------------------------------------------------------
# Homebrew bash completions
# ---------------------------------------------------------------------------
#
# Homebrew installs completion scripts to:
#   $HOMEBREW_PREFIX/etc/bash_completion.d/
#
# The main entry point (bash_completion.sh) loads all of them.
# This replaces the need to source individual completion files.
# ---------------------------------------------------------------------------

if [[ -v __homebrew_dir ]]; then
  if [[ -r "${__homebrew_dir}/etc/profile.d/bash_completion.sh" ]]; then
    # shellcheck disable=SC1091
    source "${__homebrew_dir}/etc/profile.d/bash_completion.sh"
    _status_set "completions" "ok" "$(_sc 114)bash-completion$(_sr) loaded"
  else
    _status_set "completions" "warn" "bash_completion.sh $(_sc 221)not found$(_sr)"
  fi
else
  _status_set "completions" "warn" "homebrew $(_sc 221)not available$(_sr)"
fi
