#!/usr/bin/env bash
# =============================================================================
# core/02_path.bash -- Homebrew detection and PATH construction
# =============================================================================
#
# What this module does:
#   1. Detects the Homebrew installation and exports __homebrew_dir
#   2. Builds the PATH variable with correct priority ordering
#
#   PATH priority (highest to lowest):
#     ~/opt/*/bin          User-installed tools (each subdir's bin/)
#     ~/opt/bin            General user binaries
#     ~/bin                Personal scripts
#     $HOMEBREW/bin        Homebrew-installed binaries
#     $HOMEBREW/sbin       Homebrew system binaries
#     /usr/local/bin       System-local binaries
#     /usr/bin             Core system binaries
#     ... (existing PATH)  Everything else, including /etc/paths entries
#
# Dependencies:
#   _log_error   (from lib/logging.bash)
#   _status_set  (from lib/logging.bash)
#
# Exports (global variables):
#   __homebrew_dir    Homebrew prefix path (e.g. /opt/homebrew)
#
# =============================================================================

# ---------------------------------------------------------------------------
# Helper: add a directory to PATH if it is not already present
# ---------------------------------------------------------------------------

_path_prepend() {
  local dir="$1"
  if [[ ":${PATH}:" != *":${dir}:"* ]]; then
    PATH="${dir}:${PATH}"
  fi
}

# ---------------------------------------------------------------------------
# Ensure basic system directories are on PATH
# ---------------------------------------------------------------------------

_path_prepend "/usr/bin"
_path_prepend "/usr/local/bin"

# ---------------------------------------------------------------------------
# Homebrew detection
#
# Homebrew can be installed in two locations:
#   /opt/homebrew     Apple Silicon Macs (arm64)
#   /usr/local        Intel Macs (x86_64)
#
# We run `brew --prefix` once to get the canonical path and store it in
# __homebrew_dir.  Many other modules depend on this variable.
# ---------------------------------------------------------------------------

if [[ -f /opt/homebrew/bin/brew ]]; then
  # Apple Silicon (arm64) -- the standard location since Homebrew 3.0
  __homebrew_dir="$(/opt/homebrew/bin/brew --prefix)"
elif [[ -f /usr/local/bin/brew ]]; then
  # Intel Mac (x86_64)
  __homebrew_dir="$(/usr/local/bin/brew --prefix)"
else
  _log_error "Homebrew not found at /opt/homebrew or /usr/local -- many modules will be impacted"
fi

if [[ -n "${__homebrew_dir:-}" ]]; then
  _path_prepend "${__homebrew_dir}/sbin"
  _path_prepend "${__homebrew_dir}/bin"
fi

# ---------------------------------------------------------------------------
# User binary directories
# ---------------------------------------------------------------------------

# ~/bin -- personal scripts and symlinks
_path_prepend "${HOME}/bin"

# ~/opt/bin -- manually installed tools
_path_prepend "${HOME}/opt/bin"

# ~/opt/*/bin -- each subdirectory under ~/opt that has a bin/ folder.
# This is a convention for tools installed via git clone or manual extraction
# (e.g. ~/opt/bw-select/bin/bw-select).
for _app_dir in "${HOME}"/opt/*/; do
  if [[ -d "${_app_dir}bin" ]]; then
    _path_prepend "${_app_dir}bin"
  fi
done

unset _app_dir

# ---------------------------------------------------------------------------
# Clean up -- _path_prepend is a setup-time utility, not needed at runtime
# ---------------------------------------------------------------------------

unset -f _path_prepend

# ---------------------------------------------------------------------------
# Status report
# ---------------------------------------------------------------------------

if [[ -n "${__homebrew_dir:-}" ]]; then
  _status_set "path" "ok" "homebrew: $(_sc 114)${__homebrew_dir}$(_sr)"
else
  _status_set "path" "warn" "homebrew $(_sc 221)not found$(_sr)"
fi
