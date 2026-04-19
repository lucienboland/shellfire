#!/usr/bin/env bash
# =============================================================================
# lib/logging.bash -- Logging helpers, coloured printf, and status collection
# =============================================================================
#
# What this module does:
#   Provides a suite of logging and output functions used throughout the
#   Shellfire bash configuration.  Includes the original _printf colour
#   helper for backward compatibility, plus a modern _log_* family with
#   consistent icons and formatting.
#
#   Also provides the _status_set / _status_get API for modules to report
#   their load state.  The banner renderer in lib/banner.bash reads this
#   data to build the startup dashboard.
#
# Dependencies:
#   __colours              (from lib/colours.bash)
#   __shellfire_verbose    (from shellfire.bash)
#
# Exports (functions):
#   _printf           Coloured printf (legacy helper, widely used)
#   _log_info         Informational message with cyan arrow
#   _log_ok           Success message with green tick
#   _log_warn         Warning message with yellow triangle (stderr)
#   _log_error        Error message with red cross (stderr)
#   _log_debug        Debug message -- only shown when __shellfire_verbose >= 2
#   _log_section      Section header for verbose startup output
#   _require_command  Check if a command is available, warn if not
#   _status_set       Register a module's load state and detail string
#   _status_get       Retrieve a module's load state
#   _sc               Generate a 256-colour escape for use in status details
#   _sr               Generate a reset escape for use in status details
#
# Exports (global variables):
#   __shellfire_status_state    Associative array: module -> ok|warn|error
#   __shellfire_status_detail   Associative array: module -> detail string
#   __shellfire_status_file     Associative array: module -> source filename
#   __shellfire_status_order    Indexed array: modules in load order
#
# =============================================================================

# ---------------------------------------------------------------------------
# Status collection data structures
#
# Modules call _status_set to register their state.  The banner renderer
# iterates these arrays to build the status table.
#
# State values:
#   "ok"    -- Module loaded successfully
#   "warn"  -- Module loaded but with a non-fatal issue
#   "error" -- Module failed to load or a critical dependency is missing
#
# Detail strings:
#   - May contain literal newlines (\n or $'\n') for multi-line status.
#     The first line is displayed next to the filename; continuation lines
#     are indented below the filename column.
#   - May contain ANSI escape sequences for colour.  Use the _sc and _sr
#     helpers to generate them.  The banner strips escapes when computing
#     visible width for alignment.
# ---------------------------------------------------------------------------

declare -gA __shellfire_status_state=()
declare -gA __shellfire_status_detail=()
declare -gA __shellfire_status_file=()
declare -ga __shellfire_status_order=()

# ---------------------------------------------------------------------------
# _sc -- Status colour helper
#
# Returns a 256-colour foreground escape sequence as a string.  Intended
# for embedding colour in _status_set detail strings.
#
# Usage:
#   _status_set "mod" "ok" "$(_sc 114)value$(_sr) plain text"
#
# Common colours:
#   114 = green (ok)     221 = yellow (warn)    204 = red (error)
#   75  = cyan (accent)  252 = white (bright)   243 = grey (muted)
#   109 = teal (info)    208 = orange            141 = purple
# ---------------------------------------------------------------------------

_sc() { printf '\033[38;5;%sm' "$1"; }

# ---------------------------------------------------------------------------
# _sr -- Status reset helper
#
# Returns an ANSI reset sequence.  Pair with _sc in status details.
# ---------------------------------------------------------------------------

_sr() { printf '\033[0m'; }

# ---------------------------------------------------------------------------
# _status_set -- Register a module's load state
#
# Usage:
#   _status_set <module-name> <state> <detail-string> [filename]
#
# The module-name is a short identifier (e.g. "ssh-agent", "cloud-aws").
# The state must be "ok", "warn", or "error".
# The detail string is shown in the banner.  It supports:
#   - Newlines ($'\n') for multi-line output
#   - ANSI escapes (_sc/_sr) for coloured values
# The filename is optional -- if omitted, uses __shellfire_current_file.
#
# Examples:
#   _status_set "ssh-agent" "ok" "active · pid 49129 · 2 keys"
#   _status_set "creds" "ok" "cache: $(_sc 114)fresh$(_sr)"$'\n'"token: ATLASSIAN_API_TOKEN"
# ---------------------------------------------------------------------------

_status_set() {
  local module="$1"
  local state="$2"
  local detail="$3"
  local file="${4:-${__shellfire_current_file:-unknown}}"

  __shellfire_status_state["${module}"]="${state}"
  __shellfire_status_detail["${module}"]="${detail}"
  __shellfire_status_file["${module}"]="${file}"

  # Track load order (avoid duplicates)
  local existing
  for existing in "${__shellfire_status_order[@]}"; do
    [[ "${existing}" == "${module}" ]] && return 0
  done
  __shellfire_status_order+=("${module}")
}

# ---------------------------------------------------------------------------
# _status_get -- Retrieve a module's load state
#
# Usage:
#   local state=$(_status_get "ssh-agent" state)
#   local detail=$(_status_get "ssh-agent" detail)
#   local file=$(_status_get "ssh-agent" file)
# ---------------------------------------------------------------------------

_status_get() {
  local module="$1"
  local field="${2:-state}"

  case "${field}" in
    state)  echo "${__shellfire_status_state[${module}]:-}" ;;
    detail) echo "${__shellfire_status_detail[${module}]:-}" ;;
    file)   echo "${__shellfire_status_file[${module}]:-}" ;;
  esac
}

# ---------------------------------------------------------------------------
# _printf -- Coloured printf helper (backward-compatible)
#
# Usage:
#   _printf colour format [arguments...]   Print with ANSI colour
#   _printf format [arguments...]          Plain printf (no colour match)
#
# The first argument is tested against the __colours associative array.
# If it matches a known colour name, that colour is applied to the output.
# Otherwise, all arguments are passed through to printf unchanged.
#
# Examples:
#   _printf red "Error: %s\n" "something broke"
#   _printf boldgreen "Success!\n"
#   _printf "%s\n" "no colour, just plain printf"
# ---------------------------------------------------------------------------

# shellcheck disable=SC2059
_printf() {
  local _params=("$@")

  # If two or more arguments and the first one is a recognised colour name,
  # wrap the output in that colour and reset afterward.
  if (( ${#_params[@]} >= 2 )) && [[ -n "${__colours[${_params[0]}]+defined}" ]]; then
    local _colour="${_params[0]}"
    local _format="${_params[1]}"

    printf "${__colours[${_colour}]}"
    printf "${_format}" "${_params[@]:2}"
    printf "${__colours[default]}"
  else
    # No colour match -- fall through to plain printf
    printf "${_params[@]}"
  fi
}

# ---------------------------------------------------------------------------
# Modern logging functions
#
# These use Unicode icons and consistent formatting.  They are intended for
# startup messages and interactive feedback -- not for script output that
# might be piped.
#
# Output goes to stdout except _log_warn and _log_error which go to stderr.
# ---------------------------------------------------------------------------

_log_info() {
  printf "${__colours[cyan]}  ▸${__colours[default]} %s\n" "$*"
}

_log_ok() {
  printf "${__colours[green]}  ✔${__colours[default]} %s\n" "$*"
}

_log_warn() {
  printf "${__colours[yellow]}  ⚠${__colours[default]} %s\n" "$*" >&2
}

_log_error() {
  printf "${__colours[red]}  ✘${__colours[default]} %s\n" "$*" >&2
}

# _log_debug -- Only prints when __shellfire_verbose >= 2 (trace mode).
# Use this for noisy startup tracing that should be silent by default.
# At verbose=1, only the compact startup banner is shown.
_log_debug() {
  if (( "${__shellfire_verbose:-0}" >= 2 )); then
    printf "${__colours[dimwhite]}  … %s${__colours[default]}\n" "$*"
  fi
}

# _log_section -- Print a visually distinct section header.
# Used by the module loader in shellfire.bash to announce each file being sourced.
# Only shown at verbose level 2 (trace mode).
_log_section() {
  if (( "${__shellfire_verbose:-0}" >= 2 )); then
    printf "${__colours[dimcyan]}  ── %s${__colours[default]}\n" "$*"
  fi
}

# ---------------------------------------------------------------------------
# _require_command -- Check that a command exists, warn if missing
#
# Usage:
#   _require_command "fzf" "brew install fzf" || return
#
# Returns 0 if the command is found, 1 if missing.
# The optional second argument is printed as an install hint.
# ---------------------------------------------------------------------------

_require_command() {
  local cmd_name="$1"
  local install_hint="${2:-}"

  if command -v "${cmd_name}" &>/dev/null; then
    return 0
  else
    _log_warn "Required command not found: ${cmd_name}"
    if [[ -n "${install_hint}" ]]; then
      printf "${__colours[dimwhite]}    Install: %s${__colours[default]}\n" "${install_hint}" >&2
    fi
    return 1
  fi
}
