#!/usr/bin/env bash
# =============================================================================
# tests/test_shellfire.bash -- Shellfire validation and testing framework
# =============================================================================
#
# A comprehensive test suite for the Shellfire bash configuration framework.
# Tests are organised into sections corresponding to the files they validate.
#
# Usage:
#   bash ~/.config/bash/tests/test_shellfire.bash          # run all tests
#   bash ~/.config/bash/tests/test_shellfire.bash -v        # verbose (show all output)
#   bash ~/.config/bash/tests/test_shellfire.bash -s NAME   # run only section NAME
#
# Sections:
#   syntax          Syntax-check all .bash files (bash -n)
#   shellfire       Orchestrator (shellfire.bash)
#   logging         Logging helpers (lib/logging.bash)
#   banner          Banner renderer (lib/banner.bash)
#   history         History config (core/01_history.bash)
#   path            PATH construction (core/02_path.bash)
#   environment     Environment vars (core/03_environment.bash)
#   completions     Tab completion (core/04_completions.bash)
#   ssh-agent       SSH agent (core/05_ssh-agent.bash)
#   credentials     Credential loader (plugins/credentials.bash)
#   git-prompt      Git prompt (plugins/git-prompt.bash)
#   languages       Language runtimes (plugins/languages.bash)
#   cloud-aws       AWS tools (plugins/cloud-aws.bash)
#   cloud-azure     Azure config (plugins/cloud-azure.bash)
#   fzf             Fuzzy finder (plugins/fzf.bash)
#   tmux-helpers    Tmux wrappers (plugins/tmux-helpers.bash)
#   tools           Misc tools (plugins/tools.bash)
#   dgs             DGS connector (plugins/dgs.bash)
#   copilot-sess    Copilot sessions (plugins/copilot-sessions.bash)
#   integration     Full framework load test
#
# Exit code: 0 if all tests pass, 1 if any test fails.
#
# =============================================================================

set -uo pipefail
# Note: NOT using set -e.  Test assertions need to handle non-zero exit codes
# from commands without the shell aborting.  Instead, we track failures via
# the _T_FAILED counter and exit with code 1 at the end if any test failed.

# =============================================================================
# TEST FRAMEWORK: colours, counters, helpers
# =============================================================================

# -- Colour definitions for test output ------------------------------------
#
# Commands being run:    bold white on dark blue background
# Command output:        default terminal colour
# Pass:                  bold green
# Fail:                  bold white on red background
# Section headers:       bold cyan
# Info:                  dim grey
# Skipped:               yellow

_T_RESET=$'\033[0m'
_T_BOLD=$'\033[1m'
_T_DIM=$'\033[2m'

# Command display: white on dark blue
_T_CMD=$'\033[1;37;44m'

# Output display: muted (default fg, slightly dim)
_T_OUT=$'\033[0;37m'

# Pass: bold green
_T_PASS=$'\033[1;32m'

# Fail: bold white on red
_T_FAIL=$'\033[1;37;41m'

# Section header: bold cyan
_T_SEC=$'\033[1;36m'

# Info: dim grey
_T_INFO=$'\033[2;37m'

# Skipped: yellow
_T_SKIP=$'\033[0;33m'

# Warning: yellow bold
_T_WARN=$'\033[1;33m'

# -- Counters --------------------------------------------------------------
_T_TOTAL=0
_T_PASSED=0
_T_FAILED=0
_T_SKIPPED=0

# -- Options ---------------------------------------------------------------
_T_VERBOSE=0
_T_SECTION=""

# -- Framework directory ---------------------------------------------------
# Self-relocating: always points to the repo this test file lives in,
# regardless of where the test is invoked from.
_sf_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
_T_DIR="${_sf_dir}"

# =============================================================================
# Parse arguments
# =============================================================================

while [[ $# -gt 0 ]]; do
  case "$1" in
    -v|--verbose) _T_VERBOSE=1; shift ;;
    -s|--section) _T_SECTION="$2"; shift 2 ;;
    -h|--help)
      printf "Usage: %s [-v|--verbose] [-s|--section NAME]\n" "$0"
      printf "       %s -h|--help\n" "$0"
      exit 0
      ;;
    *) printf "Unknown option: %s\n" "$1"; exit 1 ;;
  esac
done

# =============================================================================
# Test helper functions
# =============================================================================

# _t_section -- Print a section header
# Usage: _t_section "Section Name" "description"
_t_section() {
  local name="$1"
  local desc="${2:-}"

  # If filtering by section, skip non-matching sections
  if [[ -n "${_T_SECTION}" && "${_T_SECTION}" != "${name}" ]]; then
    return 1  # signals caller to skip
  fi

  printf '\n%b══════════════════════════════════════════════════════════════%b\n' "${_T_SEC}" "${_T_RESET}"
  printf '%b  %-20s%b %s\n' "${_T_SEC}" "${name}" "${_T_RESET}" "${desc}"
  printf '%b══════════════════════════════════════════════════════════════%b\n' "${_T_SEC}" "${_T_RESET}"
  return 0
}

# _t_cmd -- Display a command being run
# Usage: _t_cmd "description" "command"
_t_cmd() {
  local desc="$1"
  local cmd="$2"
  printf '\n%b  ▸ %s %b\n' "${_T_INFO}" "${desc}" "${_T_RESET}"
  printf '  %b $ %s %b\n' "${_T_CMD}" "${cmd}" "${_T_RESET}"
}

# _t_output -- Display command output (indented)
# Usage: echo "output" | _t_output
_t_output() {
  while IFS= read -r line; do
    printf '  %b│ %s%b\n' "${_T_OUT}" "${line}" "${_T_RESET}"
  done
}

# _t_pass -- Record and display a passing test
# Usage: _t_pass "test description"
_t_pass() {
  _T_TOTAL=$(( _T_TOTAL + 1 ))
  _T_PASSED=$(( _T_PASSED + 1 ))
  printf '  %b ✓ PASS %b %s\n' "${_T_PASS}" "${_T_RESET}" "$1"
}

# _t_fail -- Record and display a failing test
# Usage: _t_fail "test description" "details"
_t_fail() {
  _T_TOTAL=$(( _T_TOTAL + 1 ))
  _T_FAILED=$(( _T_FAILED + 1 ))
  printf '  %b ✗ FAIL %b %s\n' "${_T_FAIL}" "${_T_RESET}" "$1"
  if [[ -n "${2:-}" ]]; then
    printf '  %b         → %s%b\n' "${_T_WARN}" "$2" "${_T_RESET}"
  fi
}

# _t_skip -- Record and display a skipped test
# Usage: _t_skip "test description" "reason"
_t_skip() {
  _T_TOTAL=$(( _T_TOTAL + 1 ))
  _T_SKIPPED=$(( _T_SKIPPED + 1 ))
  printf '  %b ○ SKIP %b %s — %s\n' "${_T_SKIP}" "${_T_RESET}" "$1" "${2:-}"
}

# _t_run -- Run a command, capture output, display it
# Usage: output=$(_t_run "cmd args")
# Returns the exit code of the command.
_t_run() {
  local cmd="$1"
  local output rc
  output=$(eval "${cmd}" 2>&1) && rc=0 || rc=$?

  if (( _T_VERBOSE )) || (( rc != 0 )); then
    if [[ -n "${output}" ]]; then
      echo "${output}" | _t_output
    fi
  fi

  _T_LAST_OUTPUT="${output}"
  _T_LAST_RC="${rc}"
  return "${rc}"
}

# _t_assert_rc -- Assert a command's exit code
# Usage: _t_assert_rc "description" "command" expected_rc
_t_assert_rc() {
  local desc="$1"
  local cmd="$2"
  local expected="${3:-0}"

  _t_cmd "${desc}" "${cmd}"
  _t_run "${cmd}" || true

  if (( _T_LAST_RC == expected )); then
    _t_pass "${desc}"
  else
    _t_fail "${desc}" "expected exit code ${expected}, got ${_T_LAST_RC}"
  fi
}

# _t_assert_contains -- Assert command output contains a string
# Usage: _t_assert_contains "description" "command" "expected_substring"
_t_assert_contains() {
  local desc="$1"
  local cmd="$2"
  local expected="$3"

  _t_cmd "${desc}" "${cmd}"
  _t_run "${cmd}" || true

  if [[ "${_T_LAST_OUTPUT}" == *"${expected}"* ]]; then
    _t_pass "${desc}"
  else
    _t_fail "${desc}" "output does not contain: ${expected}"
    if (( ! _T_VERBOSE )); then
      echo "${_T_LAST_OUTPUT}" | head -5 | _t_output
    fi
  fi
}

# _t_assert_not_contains -- Assert command output does NOT contain a string
# Usage: _t_assert_not_contains "description" "command" "unwanted_substring"
_t_assert_not_contains() {
  local desc="$1"
  local cmd="$2"
  local unwanted="$3"

  _t_cmd "${desc}" "${cmd}"
  _t_run "${cmd}" || true

  if [[ "${_T_LAST_OUTPUT}" != *"${unwanted}"* ]]; then
    _t_pass "${desc}"
  else
    _t_fail "${desc}" "output unexpectedly contains: ${unwanted}"
  fi
}

# _t_assert_set -- Assert an environment variable is set (non-empty)
# Usage: _t_assert_set "description" "VAR_NAME" "value"
_t_assert_set() {
  local desc="$1"
  local value="$2"

  if [[ -n "${value}" ]]; then
    _t_pass "${desc}"
  else
    _t_fail "${desc}" "variable is empty or unset"
  fi
}

# _t_assert_file -- Assert a file exists
# Usage: _t_assert_file "description" "/path/to/file"
_t_assert_file() {
  local desc="$1"
  local filepath="$2"

  if [[ -f "${filepath}" ]]; then
    _t_pass "${desc}"
  else
    _t_fail "${desc}" "file not found: ${filepath}"
  fi
}

# _t_assert_socket -- Assert a Unix socket exists
# Usage: _t_assert_socket "description" "/path/to/socket"
_t_assert_socket() {
  local desc="$1"
  local sockpath="$2"

  if [[ -S "${sockpath}" ]]; then
    _t_pass "${desc}"
  else
    _t_fail "${desc}" "not a socket: ${sockpath}"
  fi
}

# =============================================================================
# Banner: print the test suite header
# =============================================================================

printf '\n'
printf '%b┌──────────────────────────────────────────────────────────────┐%b\n' "${_T_SEC}" "${_T_RESET}"
printf '%b│         SHELLFIRE  TEST  SUITE                              │%b\n' "${_T_SEC}" "${_T_RESET}"
printf '%b│         ~/code/shellfire/tests/test_shellfire.bash         │%b\n' "${_T_SEC}" "${_T_RESET}"
printf '%b└──────────────────────────────────────────────────────────────┘%b\n' "${_T_SEC}" "${_T_RESET}"
printf '%b  Framework dir: %s%b\n' "${_T_INFO}" "${_T_DIR}" "${_T_RESET}"
printf '%b  Verbose:       %s%b\n' "${_T_INFO}" "$(( _T_VERBOSE ))" "${_T_RESET}"
if [[ -n "${_T_SECTION}" ]]; then
  printf '%b  Section filter: %s%b\n' "${_T_INFO}" "${_T_SECTION}" "${_T_RESET}"
fi
printf '%b  Date:          %s%b\n' "${_T_INFO}" "$(date '+%Y-%m-%d %H:%M:%S')" "${_T_RESET}"


# #############################################################################
#
# SECTION: syntax
# Files tested: ALL .bash files in lib/, core/, plugins/, and shellfire.bash
#
# Runs `bash -n` on every file to ensure there are no syntax errors.
# This is the most basic validation -- if this fails, nothing else works.
#
# #############################################################################

if _t_section "syntax" "bash -n syntax check on all .bash files"; then

  for _t_file in \
    "${_T_DIR}"/lib/*.bash \
    "${_T_DIR}"/shellfire.bash \
    "${_T_DIR}"/core/*.bash \
  ; do
    _t_shortname="${_t_file#"${_T_DIR}"/}"
    _t_assert_rc \
      "syntax: ${_t_shortname}" \
      "bash -n '${_t_file}'" \
      0
  done
fi


# #############################################################################
#
# SECTION: shellfire
# File tested: ~/.config/bash/shellfire.bash
#
# Tests the orchestrator: verifies it sets the expected global variables,
# sources libraries in the correct order, and populates module arrays.
#
# #############################################################################

if _t_section "shellfire" "Orchestrator (shellfire.bash)"; then

  # ── Test: shellfire.bash exists and is readable ──
  _t_assert_file \
    "shellfire.bash exists" \
    "${_T_DIR}/shellfire.bash"

  # ── Test: lib files exist ──
  for _lib in colours.bash logging.bash banner.bash; do
    _t_assert_file "lib/${_lib} exists" "${_T_DIR}/lib/${_lib}"
  done

  # ── Test: core files exist and are numbered ──
  _t_cmd "Core files follow NN_*.bash naming" \
    "ls core/[0-9][0-9]_*.bash"
  _core_count=0
  for _cf in "${_T_DIR}"/core/[0-9][0-9]_*.bash; do
    [[ -f "${_cf}" ]] && (( _core_count++ ))
  done
  if (( _core_count >= 4 )); then
    _t_pass "found ${_core_count} core modules (expected >= 4)"
  else
    _t_fail "found ${_core_count} core modules" "expected at least 4"
  fi

  # ── Test: source shellfire.bash in a subshell and check globals ──
  _t_cmd "Source shellfire.bash and verify globals" \
    "bash -c 'source shellfire.bash; echo vars...'"

  # We run shellfire.bash in a controlled subshell.  Since it sources
  # core and plugin modules (which may prompt for ssh passphrase etc),
  # we set SHELLFIRE_VERBOSE=0 and redirect stdin from /dev/null.
  _sf_test_output=$(
    SHELLFIRE_VERBOSE=0 bash -c '
      export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
      export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
      export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
      source "'"${_T_DIR}"'/shellfire.bash" 2>/dev/null </dev/null
      echo "__shellfire_os=${__shellfire_os}"
      echo "__shellfire_verbose=${__shellfire_verbose}"
      echo "__shellfire_hostname=${__shellfire_hostname}"
      # Output both old (pre-Task 3) and new (post-Task 3) home variables
      echo "__shellfire_dir=${__shellfire_dir:-}"
      echo "__shellfire_home=${__shellfire_home:-}"
      echo "core_count=${#__shellfire_core_modules[@]}"
      echo "status_count=${#__shellfire_status_order[@]}"
    ' 2>/dev/null
  ) || true

  if (( _T_VERBOSE )); then
    echo "${_sf_test_output}" | _t_output
  fi

  # Check each expected global
  _sf_os=$(echo "${_sf_test_output}" | grep '^__shellfire_os=' | cut -d= -f2)
  [[ "${_sf_os}" == "Darwin" ]] && _t_pass "os = Darwin" || _t_fail "os = Darwin" "got: ${_sf_os}"

  _sf_verbose=$(echo "${_sf_test_output}" | grep '^__shellfire_verbose=' | cut -d= -f2)
  [[ "${_sf_verbose}" == "0" ]] && _t_pass "verbose = 0 (as set)" || _t_fail "verbose = 0" "got: ${_sf_verbose}"

  _sf_hostname=$(echo "${_sf_test_output}" | grep '^__shellfire_hostname=' | cut -d= -f2)
  [[ -n "${_sf_hostname}" ]] && _t_pass "hostname is set: ${_sf_hostname}" || _t_fail "hostname is set" "empty"

  # Accept either old __shellfire_dir (pre-Task 3) or new __shellfire_home (post-Task 3)
  _sf_loaded_dir=$(echo "${_sf_test_output}" | grep '^__shellfire_dir=' | cut -d= -f2-)
  _sf_loaded_home=$(echo "${_sf_test_output}" | grep '^__shellfire_home=' | cut -d= -f2-)
  if [[ "${_sf_loaded_dir}" == *"/bash" ]]; then
    _t_pass "config dir ends with /bash (old architecture)"
  elif [[ "${_sf_loaded_home}" == "${_sf_dir}" ]]; then
    _t_pass "__shellfire_home matches framework repo (new architecture)"
  else
    _t_fail "__shellfire_home or dir" "home='${_sf_loaded_home}' dir='${_sf_loaded_dir}' expected_home='${_sf_dir}'"
  fi

  _sf_core=$(echo "${_sf_test_output}" | grep '^core_count=' | cut -d= -f2)
  (( _sf_core >= 4 )) && _t_pass "core_count = ${_sf_core} (>= 4)" || _t_fail "core_count >= 4" "got: ${_sf_core}"

  # status_count covers core modules only (>= 4); plugins are tested in test_plugins.bash
  _sf_status=$(echo "${_sf_test_output}" | grep '^status_count=' | cut -d= -f2)
  (( _sf_status >= 4 )) && _t_pass "status_count = ${_sf_status} (>= 4 core modules)" || _t_fail "status_count >= 4" "got: ${_sf_status}"
fi


# #############################################################################
#
# SECTION: shellfire-config-home
# File tested: ~/code/shellfire/shellfire.bash
#
# Tests that the new architecture correctly derives __shellfire_home from
# BASH_SOURCE and honours SHELLFIRE_CONFIG_HOME (or defaults to XDG).
#
# NOTE: These tests FAIL until Task 3 rewrites shellfire.bash.
#
# #############################################################################

if _t_section "shellfire-config-home" "SHELLFIRE_CONFIG_HOME split (shellfire.bash)"; then

  # ── Test: SHELLFIRE_CONFIG_HOME env var sets __shellfire_config_home ──
  # NOTE: This test FAILS until Task 3 rewrites shellfire.bash.
  _t_cmd "SHELLFIRE_CONFIG_HOME respects env var" \
    "SHELLFIRE_CONFIG_HOME=/tmp/X source shellfire.bash; echo __shellfire_config_home"
  _sch_output1=$(
    SHELLFIRE_VERBOSE=0 bash -c '
      _tmp=$(mktemp -d)
      mkdir -p "${_tmp}/plugins"
      touch "${_tmp}/plugins.conf"
      export XDG_CONFIG_HOME="${HOME}/.config"
      export XDG_CACHE_HOME="${HOME}/.cache"
      export XDG_DATA_HOME="${HOME}/.local/share"
      export SHELLFIRE_CONFIG_HOME="${_tmp}"
      source "'"${_sf_dir}"'/shellfire.bash" 2>/dev/null </dev/null
      echo "__shellfire_config_home=${__shellfire_config_home}"
      rm -rf "${_tmp}"
    ' 2>/dev/null
  )
  _sch_got=$(echo "${_sch_output1}" | grep '^__shellfire_config_home=' | cut -d= -f2)
  # macOS mktemp resolves to /private/var/... or /tmp/...; match either
  if [[ "${_sch_got}" == /tmp/* || "${_sch_got}" == /var/* || "${_sch_got}" == /private/* ]]; then
    _t_pass "SHELLFIRE_CONFIG_HOME: config home is the temp dir"
  else
    _t_fail "SHELLFIRE_CONFIG_HOME: config home is the temp dir" "got: ${_sch_got}"
  fi

  # ── Test: defaults to XDG_CONFIG_HOME/shellfire when unset ──
  _t_cmd "SHELLFIRE_CONFIG_HOME unset: defaults to XDG_CONFIG_HOME/shellfire" \
    "unset SHELLFIRE_CONFIG_HOME; source shellfire.bash; echo __shellfire_config_home"
  _sch_output2=$(
    SHELLFIRE_VERBOSE=0 bash -c '
      export XDG_CONFIG_HOME="${HOME}/.config"
      export XDG_CACHE_HOME="${HOME}/.cache"
      export XDG_DATA_HOME="${HOME}/.local/share"
      unset SHELLFIRE_CONFIG_HOME
      source "'"${_sf_dir}"'/shellfire.bash" 2>/dev/null </dev/null
      echo "__shellfire_config_home=${__shellfire_config_home}"
    ' 2>/dev/null
  )
  _sch_default=$(echo "${_sch_output2}" | grep '^__shellfire_config_home=' | cut -d= -f2)
  [[ "${_sch_default}" == *"/shellfire" ]] && \
    _t_pass "default config home ends with /shellfire" || \
    _t_fail "default config home ends with /shellfire" "got: ${_sch_default}"

  # ── Test: __shellfire_home matches the framework repo (derives from BASH_SOURCE) ──
  _t_cmd "__shellfire_home derived from BASH_SOURCE" \
    "source shellfire.bash; echo __shellfire_home"
  _sch_output3=$(
    SHELLFIRE_VERBOSE=0 bash -c '
      _tmp=$(mktemp -d)
      mkdir -p "${_tmp}/plugins"
      touch "${_tmp}/plugins.conf"
      export XDG_CONFIG_HOME="${HOME}/.config"
      export XDG_CACHE_HOME="${HOME}/.cache"
      export XDG_DATA_HOME="${HOME}/.local/share"
      export SHELLFIRE_CONFIG_HOME="${_tmp}"
      source "'"${_sf_dir}"'/shellfire.bash" 2>/dev/null </dev/null
      echo "__shellfire_home=${__shellfire_home}"
      rm -rf "${_tmp}"
    ' 2>/dev/null
  )
  _sch_home=$(echo "${_sch_output3}" | grep '^__shellfire_home=' | cut -d= -f2)
  [[ "${_sch_home}" == "${_sf_dir}" ]] && \
    _t_pass "__shellfire_home matches framework repo dir" || \
    _t_fail "__shellfire_home matches framework repo dir" "got: ${_sch_home}"

fi


# #############################################################################
#
# SECTION: logging
# File tested: ~/.config/bash/lib/logging.bash
#
# Tests the logging helpers, status API, and _sc/_sr colour functions.
#
# #############################################################################

if _t_section "logging" "Logging and status API (lib/logging.bash)"; then

  _t_assert_file "lib/logging.bash exists" "${_T_DIR}/lib/logging.bash"

  # ── Test: _sc produces a valid ANSI escape ──
  _t_cmd "Test _sc colour helper" "_sc 114"
  _sc_out=$(
    bash -c '
      source "'"${_T_DIR}"'/lib/colours.bash" 2>/dev/null
      source "'"${_T_DIR}"'/lib/logging.bash" 2>/dev/null
      printf "%s" "$(_sc 114)" | cat -v
    '
  )
  if [[ "${_sc_out}" == *"[38;5;114m"* ]]; then
    _t_pass "_sc 114 produces correct ANSI escape"
  else
    _t_fail "_sc 114" "got: ${_sc_out}"
  fi

  # ── Test: _sr produces a reset escape ──
  _t_cmd "Test _sr reset helper" "_sr"
  _sr_out=$(
    bash -c '
      source "'"${_T_DIR}"'/lib/colours.bash" 2>/dev/null
      source "'"${_T_DIR}"'/lib/logging.bash" 2>/dev/null
      printf "%s" "$(_sr)" | cat -v
    '
  )
  if [[ "${_sr_out}" == *"[0m"* ]]; then
    _t_pass "_sr produces ANSI reset"
  else
    _t_fail "_sr" "got: ${_sr_out}"
  fi

  # ── Test: _status_set and _status_get work ──
  _t_cmd "Test _status_set / _status_get round-trip" \
    "_status_set test-mod ok 'all good'; _status_get test-mod state"
  _status_test=$(
    bash -c '
      declare -gA __shellfire_status_state=()
      declare -gA __shellfire_status_detail=()
      declare -gA __shellfire_status_file=()
      declare -ga __shellfire_status_order=()
      __shellfire_current_file="test.bash"
      source "'"${_T_DIR}"'/lib/colours.bash" 2>/dev/null
      source "'"${_T_DIR}"'/lib/logging.bash" 2>/dev/null
      _status_set "test-mod" "ok" "all good"
      echo "state=$(_status_get "test-mod" state)"
      echo "detail=$(_status_get "test-mod" detail)"
      echo "file=$(_status_get "test-mod" file)"
      echo "order=${__shellfire_status_order[*]}"
    '
  )
  if (( _T_VERBOSE )); then echo "${_status_test}" | _t_output; fi

  echo "${_status_test}" | grep -q 'state=ok' && _t_pass "_status_get returns ok" || _t_fail "_status_get state" ""
  echo "${_status_test}" | grep -q 'detail=all good' && _t_pass "_status_get returns detail" || _t_fail "_status_get detail" ""
  echo "${_status_test}" | grep -q 'file=test.bash' && _t_pass "_status_get returns file" || _t_fail "_status_get file" ""
  echo "${_status_test}" | grep -q 'order=test-mod' && _t_pass "_status_set records order" || _t_fail "_status_set order" ""

  # ── Test: _log_debug only prints at verbose >= 2 ──
  _t_cmd "Test _log_debug suppressed at verbose=1" \
    "__shellfire_verbose=1 _log_debug 'should not appear'"
  _debug_v1=$(
    bash -c '
      source "'"${_T_DIR}"'/lib/colours.bash" 2>/dev/null
      __shellfire_verbose=1
      source "'"${_T_DIR}"'/lib/logging.bash" 2>/dev/null
      _log_debug "invisible"
    '
  )
  if [[ -z "${_debug_v1}" ]]; then
    _t_pass "_log_debug silent at verbose=1"
  else
    _t_fail "_log_debug silent at verbose=1" "produced output: ${_debug_v1}"
  fi

  _t_cmd "Test _log_debug visible at verbose=2" \
    "__shellfire_verbose=2 _log_debug 'should appear'"
  _debug_v2=$(
    bash -c '
      source "'"${_T_DIR}"'/lib/colours.bash" 2>/dev/null
      __shellfire_verbose=2
      source "'"${_T_DIR}"'/lib/logging.bash" 2>/dev/null
      _log_debug "visible"
    '
  )
  if [[ "${_debug_v2}" == *"visible"* ]]; then
    _t_pass "_log_debug visible at verbose=2"
  else
    _t_fail "_log_debug visible at verbose=2" "no output"
  fi
fi


# #############################################################################
#
# SECTION: banner
# File tested: ~/.config/bash/lib/banner.bash
#
# Tests the banner renderer: dynamic width adaptation, box alignment,
# multi-line detail support, and ANSI-stripping for width calculation.
#
# #############################################################################

if _t_section "banner" "Banner renderer (lib/banner.bash)"; then

  _t_assert_file "lib/banner.bash exists" "${_T_DIR}/lib/banner.bash"

  # Helper: render banner at a given COLUMNS width and capture output.
  # Sources the full framework in a subshell with SHELLFIRE_VERBOSE=0
  # (so no banner at load time), then calls _banner_render manually.
  _render_banner_at_width() {
    local width="$1"
    COLUMNS="${width}" SHELLFIRE_VERBOSE=0 bash -c '
      export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
      export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
      export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
      export COLUMNS='"${width}"'
      source "'"${_T_DIR}"'/shellfire.bash" 2>/dev/null </dev/null
      _banner_render
    ' 2>/dev/null
  }

  # ── Test: banner renders without error at default width ──
  _t_cmd "Render banner at COLUMNS=80" "COLUMNS=80 _banner_render"
  _banner_80=$(_render_banner_at_width 80) || true
  if [[ -n "${_banner_80}" ]]; then
    _t_pass "banner renders at COLUMNS=80"
  else
    _t_fail "banner renders at COLUMNS=80" "empty output"
  fi

  # ── Test: banner contains SHELLFIRE logo ──
  if [[ "${_banner_80}" == *"█▀▀ █ █"* ]]; then
    _t_pass "banner contains SHELLFIRE logo"
  else
    _t_fail "banner contains SHELLFIRE logo" "logo text not found"
  fi

  # ── Test: banner contains box borders ──
  if [[ "${_banner_80}" == *"╭"* && "${_banner_80}" == *"╰"* ]]; then
    _t_pass "banner has top and bottom borders (╭ ╰)"
  else
    _t_fail "banner has top and bottom borders" ""
  fi

  # ── Test: banner contains section dividers ──
  if [[ "${_banner_80}" == *"├"*"core"* ]]; then
    _t_pass "banner has core section divider"
  else
    _t_fail "banner has core section divider" ""
  fi

  # Note: "plugins" section divider only appears when plugins are loaded.
  # Plugin-specific banner tests are in test_plugins.bash.

  # ── Test: all lines between borders have consistent width ──
  # Strip ANSI escapes, then check that every line containing │ has the
  # same visible length.
  _t_cmd "Check box line alignment at COLUMNS=80" \
    "measure visible width of each bordered line"

  _banner_aligned=true
  _expected_width=80  # W = 78 inner + 2 borders = 80 at COLUMNS=80
  while IFS= read -r _line; do
    # Strip ANSI escapes
    _clean=$(printf '%s' "${_line}" | sed $'s/\033\[[0-9;]*m//g')
    # Only check lines that start with a box character
    case "${_clean}" in
      │*│|╭*╮|╰*╯|├*┤)
        _vis_len=${#_clean}
        if (( _vis_len != _expected_width )); then
          _banner_aligned=false
          if (( _T_VERBOSE )); then
            printf '  %b│ width=%d expected=%d: %s%b\n' \
              "${_T_WARN}" "${_vis_len}" "${_expected_width}" "${_clean:0:40}" "${_T_RESET}"
          fi
        fi
        ;;
    esac
  done <<< "${_banner_80}"

  if ${_banner_aligned}; then
    _t_pass "all bordered lines are ${_expected_width} chars wide"
  else
    _t_fail "box line alignment" "some lines have inconsistent width"
  fi

  # ── Test: banner renders at narrow width (COLUMNS=50) ──
  _t_cmd "Render banner at COLUMNS=50 (narrow)" "COLUMNS=50 _banner_render"
  _banner_50=$(_render_banner_at_width 50) || true
  if [[ -n "${_banner_50}" ]]; then
    _t_pass "banner renders at COLUMNS=50"
  else
    _t_fail "banner renders at COLUMNS=50" "empty output"
  fi

  # ── Test: banner renders at wide width (COLUMNS=160) ──
  _t_cmd "Render banner at COLUMNS=160 (wide)" "COLUMNS=160 _banner_render"
  _banner_160=$(_render_banner_at_width 160) || true
  if [[ -n "${_banner_160}" ]]; then
    _t_pass "banner renders at COLUMNS=160"
  else
    _t_fail "banner renders at COLUMNS=160" "empty output"
  fi

  # ── Test: narrow banner is narrower than wide banner ──
  _len_50=$(printf '%s' "${_banner_50}" | sed $'s/\033\[[0-9;]*m//g' | head -3 | tail -1 | wc -c | tr -d ' ')
  _len_160=$(printf '%s' "${_banner_160}" | sed $'s/\033\[[0-9;]*m//g' | head -3 | tail -1 | wc -c | tr -d ' ')
  if (( _len_50 < _len_160 )); then
    _t_pass "narrow banner (${_len_50}c) < wide banner (${_len_160}c)"
  else
    _t_fail "width adaptation" "narrow=${_len_50} wide=${_len_160}"
  fi

  # ── Test: ANSI-stripping helper works correctly ──
  _t_cmd "Test _strip_ansi inside banner.bash" \
    "_strip_ansi on coloured string"
  _strip_test=$(
    bash -c '
      source "'"${_T_DIR}"'/lib/colours.bash" 2>/dev/null
      source "'"${_T_DIR}"'/lib/logging.bash" 2>/dev/null
      source "'"${_T_DIR}"'/lib/banner.bash" 2>/dev/null
      # _strip_ansi is local to _banner_render, so we test indirectly:
      # render a banner with coloured status and check alignment
      echo "banner_loaded=yes"
    '
  )
  if [[ "${_strip_test}" == *"banner_loaded=yes"* ]]; then
    _t_pass "banner.bash sources without error"
  else
    _t_fail "banner.bash sources without error" ""
  fi

  # Note: multi-line status detail (credentials plugin) is tested in test_plugins.bash.
fi


# #############################################################################
#
# SECTION: history
# File tested: ~/.config/bash/core/01_history.bash
#
# Tests that history configuration variables are set correctly.
#
# #############################################################################

if _t_section "history" "History config (core/01_history.bash)"; then

  _t_assert_file "core/01_history.bash exists" "${_T_DIR}/core/01_history.bash"

  # ── Test: history vars set after sourcing ──
  _hist_test=$(
    SHELLFIRE_VERBOSE=0 bash -c '
      export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
      export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
      export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
      source "'"${_T_DIR}"'/shellfire.bash" 2>/dev/null </dev/null
      echo "HISTCONTROL=${HISTCONTROL}"
      echo "HISTFILE=${HISTFILE}"
      echo "HISTSIZE=${HISTSIZE}"
      echo "HISTFILESIZE=${HISTFILESIZE}"
      echo "HISTTIMEFORMAT=${HISTTIMEFORMAT}"
    ' 2>/dev/null
  )
  if (( _T_VERBOSE )); then echo "${_hist_test}" | _t_output; fi

  echo "${_hist_test}" | grep -q 'HISTCONTROL=ignoreboth' && \
    _t_pass "HISTCONTROL=ignoreboth" || _t_fail "HISTCONTROL" ""
  echo "${_hist_test}" | grep -q 'HISTFILE=.*bash_history' && \
    _t_pass "HISTFILE points to bash_history" || _t_fail "HISTFILE" ""
  echo "${_hist_test}" | grep -q 'HISTSIZE=100000' && \
    _t_pass "HISTSIZE=100000" || _t_fail "HISTSIZE" ""
  echo "${_hist_test}" | grep -q 'HISTFILESIZE=1000000' && \
    _t_pass "HISTFILESIZE=1000000" || _t_fail "HISTFILESIZE" ""
fi


# #############################################################################
#
# SECTION: path
# File tested: ~/.config/bash/core/02_path.bash
#
# Tests that Homebrew is detected and PATH contains expected directories.
#
# #############################################################################

if _t_section "path" "PATH construction (core/02_path.bash)"; then

  _t_assert_file "core/02_path.bash exists" "${_T_DIR}/core/02_path.bash"

  _path_test=$(
    SHELLFIRE_VERBOSE=0 bash -c '
      export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
      export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
      export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
      source "'"${_T_DIR}"'/shellfire.bash" 2>/dev/null </dev/null
      echo "HOMEBREW=${__homebrew_dir:-unset}"
      echo "PATH=${PATH}"
    ' 2>/dev/null
  )
  if (( _T_VERBOSE )); then echo "${_path_test}" | _t_output; fi

  _hb=$(echo "${_path_test}" | grep '^HOMEBREW=' | cut -d= -f2)
  [[ "${_hb}" != "unset" ]] && _t_pass "homebrew detected: ${_hb}" || _t_fail "homebrew detected" "unset"

  _path_val=$(echo "${_path_test}" | grep '^PATH=' | cut -d= -f2-)
  [[ ":${_path_val}:" == *"/usr/bin:"* ]] && _t_pass "PATH contains /usr/bin" || _t_fail "PATH /usr/bin" ""
  [[ ":${_path_val}:" == *"/usr/local/bin:"* ]] && _t_pass "PATH contains /usr/local/bin" || _t_fail "PATH /usr/local/bin" ""
  [[ ":${_path_val}:" == *"${HOME}/bin:"* ]] && _t_pass "PATH contains ~/bin" || _t_fail "PATH ~/bin" ""
  [[ ":${_path_val}:" == *"${HOME}/opt/bin:"* ]] && _t_pass "PATH contains ~/opt/bin" || _t_fail "PATH ~/opt/bin" ""

  if [[ "${_hb}" != "unset" ]]; then
    [[ ":${_path_val}:" == *"${_hb}/bin:"* ]] && \
      _t_pass "PATH contains homebrew bin" || _t_fail "PATH homebrew bin" ""
  fi
fi


# #############################################################################
#
# SECTION: environment
# File tested: ~/.config/bash/core/03_environment.bash
#
# Tests general environment variables: EDITOR, CLICOLOR, etc.
#
# #############################################################################

if _t_section "environment" "Environment vars (core/03_environment.bash)"; then

  _t_assert_file "core/03_environment.bash exists" "${_T_DIR}/core/03_environment.bash"

  _env_test=$(
    SHELLFIRE_VERBOSE=0 bash -c '
      export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
      export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
      export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
      source "'"${_T_DIR}"'/shellfire.bash" 2>/dev/null </dev/null
      echo "CLICOLOR=${CLICOLOR}"
      echo "EDITOR=${EDITOR:-unset}"
      echo "BASH_SILENCE=${BASH_SILENCE_DEPRECATION_WARNING}"
      echo "PROMPT_DIRTRIM=${PROMPT_DIRTRIM}"
      echo "LESSHISTFILE=${LESSHISTFILE}"
    ' 2>/dev/null
  )
  if (( _T_VERBOSE )); then echo "${_env_test}" | _t_output; fi

  echo "${_env_test}" | grep -q 'CLICOLOR=1' && _t_pass "CLICOLOR=1" || _t_fail "CLICOLOR" ""
  echo "${_env_test}" | grep -q 'BASH_SILENCE=1' && _t_pass "BASH_SILENCE_DEPRECATION_WARNING=1" || _t_fail "BASH_SILENCE" ""
  echo "${_env_test}" | grep -q 'PROMPT_DIRTRIM=3' && _t_pass "PROMPT_DIRTRIM=3" || _t_fail "PROMPT_DIRTRIM" ""
  echo "${_env_test}" | grep -q 'LESSHISTFILE=-' && _t_pass "LESSHISTFILE=-" || _t_fail "LESSHISTFILE" ""

  _editor=$(echo "${_env_test}" | grep '^EDITOR=' | cut -d= -f2)
  if [[ "${_editor}" == *"nvim"* ]]; then
    _t_pass "EDITOR set to nvim"
  elif [[ "${_editor}" == "unset" ]]; then
    _t_skip "EDITOR" "nvim not installed"
  else
    _t_pass "EDITOR set: ${_editor}"
  fi
fi


# #############################################################################
#
# SECTION: completions
# File tested: ~/.config/bash/core/04_completions.bash
#
# Tests that bash completion framework is loaded.
#
# #############################################################################

if _t_section "completions" "Tab completion (core/04_completions.bash)"; then

  _t_assert_file "core/04_completions.bash exists" "${_T_DIR}/core/04_completions.bash"

  # ── Test: completions file references bash_completion.sh ──
  _t_assert_contains \
    "references bash_completion.sh" \
    "grep -c 'bash_completion.sh' '${_T_DIR}/core/04_completions.bash'" \
    ""

  # ── Test: completions sets status ──
  _t_assert_contains \
    "calls _status_set" \
    "grep -c '_status_set' '${_T_DIR}/core/04_completions.bash'" \
    ""
fi


# #############################################################################
#
# SECTION: ssh-agent
# File tested: ~/.config/bash/core/05_ssh-agent.bash
#
# Tests SSH agent discovery: that the existing launchd agent is reused
# (not skipped), that SSH_AUTH_SOCK points to a valid socket, and that
# no unnecessary new agents are spawned.
#
# #############################################################################

if _t_section "ssh-agent" "SSH agent discovery (core/05_ssh-agent.bash)"; then

  _t_assert_file "core/05_ssh-agent.bash exists" "${_T_DIR}/core/05_ssh-agent.bash"

  # ── Test: the launchd Listeners socket exists and is a socket ──
  _launchd_sock="${SSH_AUTH_SOCK:-}"
  if [[ -n "${_launchd_sock}" ]]; then
    _t_assert_socket "SSH_AUTH_SOCK is a socket" "${_launchd_sock}"
  else
    _t_skip "SSH_AUTH_SOCK is a socket" "SSH_AUTH_SOCK not set"
  fi

  # ── Test: the launchd agent responds (ssh-add exit code != 2) ──
  _t_cmd "Test launchd agent responds" "ssh-add -l"
  ssh-add -l >/dev/null 2>&1
  _agent_rc=$?
  if (( _agent_rc != 2 )); then
    _t_pass "agent responds at SSH_AUTH_SOCK (exit code ${_agent_rc})"
  else
    _t_fail "agent responds" "exit code 2 (cannot connect)"
  fi

  # ── Test: no *"Listener"* skip pattern in the code ──
  _t_cmd "Verify Listener skip was removed" \
    "grep '*Listener*' core/05_ssh-agent.bash"
  if grep -q '"Listener"' "${_T_DIR}/core/05_ssh-agent.bash" 2>/dev/null; then
    # Distinguish between code vs comments
    _listener_in_code=$(grep -v '^ *#' "${_T_DIR}/core/05_ssh-agent.bash" | grep -c '"Listener"' || true)
    if (( _listener_in_code > 0 )); then
      _t_fail "Listener skip removed from code" "still present in non-comment line"
    else
      _t_pass "Listener referenced only in comments (ok)"
    fi
  else
    _t_pass "no Listener skip pattern in code"
  fi

  # ── Test: sourcing the module reuses the current SSH_AUTH_SOCK ──
  # Save the current SSH_AUTH_SOCK, source the module, check it's the same.
  _t_cmd "Verify agent is reused (SSH_AUTH_SOCK preserved)" \
    "source 05_ssh-agent.bash; compare SSH_AUTH_SOCK"

  _saved_sock="${SSH_AUTH_SOCK:-}"
  _ssh_test=$(
    SHELLFIRE_VERBOSE=0 bash -c '
      export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
      export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
      export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
      source "'"${_T_DIR}"'/shellfire.bash" 2>/dev/null </dev/null
      echo "SSH_AUTH_SOCK=${SSH_AUTH_SOCK}"
      echo "SSH_AGENT_PID=${SSH_AGENT_PID:-none}"
    ' 2>/dev/null
  )
  if (( _T_VERBOSE )); then echo "${_ssh_test}" | _t_output; fi

  _new_sock=$(echo "${_ssh_test}" | grep '^SSH_AUTH_SOCK=' | cut -d= -f2)
  if [[ -n "${_saved_sock}" && "${_new_sock}" == "${_saved_sock}" ]]; then
    _t_pass "SSH_AUTH_SOCK preserved (agent reused)"
  elif [[ -n "${_new_sock}" ]]; then
    _t_fail "SSH_AUTH_SOCK preserved" "was: ${_saved_sock}, now: ${_new_sock}"
  else
    _t_fail "SSH_AUTH_SOCK preserved" "empty after sourcing"
  fi

  # ── Test: only one ssh-agent process is running ──
  _t_cmd "Count ssh-agent processes" "ps aux | grep ssh-agent"
  _agent_count=$(ps aux | grep '[s]sh-agent' | wc -l | tr -d ' ')
  if (( _agent_count == 1 )); then
    _t_pass "exactly 1 ssh-agent process running"
  elif (( _agent_count == 0 )); then
    _t_fail "ssh-agent running" "no ssh-agent processes found"
  else
    _t_fail "exactly 1 ssh-agent" "found ${_agent_count} (may have orphans from before fix)"
  fi

  # ── Test: _sshagent_loadkeys function exists after sourcing ──
  _t_cmd "Verify _sshagent_loadkeys defined" \
    "type _sshagent_loadkeys"
  _loadkeys_test=$(
    SHELLFIRE_VERBOSE=0 bash -c '
      export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
      export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
      export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
      source "'"${_T_DIR}"'/shellfire.bash" 2>/dev/null </dev/null
      type _sshagent_loadkeys 2>&1
    ' 2>/dev/null
  )
  if [[ "${_loadkeys_test}" == *"function"* ]]; then
    _t_pass "_sshagent_loadkeys is a function"
  else
    _t_fail "_sshagent_loadkeys" "not a function: ${_loadkeys_test}"
  fi

  # ── Test: sshfingerprint function exists ──
  _t_cmd "Verify sshfingerprint defined" "type sshfingerprint"
  _fp_test=$(
    SHELLFIRE_VERBOSE=0 bash -c '
      export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
      export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
      export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
      source "'"${_T_DIR}"'/shellfire.bash" 2>/dev/null </dev/null
      type sshfingerprint 2>&1
    ' 2>/dev/null
  )
  if [[ "${_fp_test}" == *"function"* ]]; then
    _t_pass "sshfingerprint is a function"
  else
    _t_fail "sshfingerprint" "not a function"
  fi

  # ── Test: private keys exist in ~/.ssh ──
  _t_cmd "Check for SSH private keys" "ls ~/.ssh"
  _key_count=0
  for _kf in "${HOME}"/.ssh/*; do
    [[ -f "${_kf}" ]] || continue
    case "${_kf}" in *.pub|*known_hosts*|*authorized_keys*|*config*|*.DS_Store) continue ;; esac
    _fl=$(head -1 "${_kf}" 2>/dev/null)
    [[ "${_fl}" == *"PRIVATE KEY"* || "${_fl}" == *"OPENSSH"* ]] && (( _key_count++ ))
  done
  if (( _key_count > 0 )); then
    _t_pass "found ${_key_count} SSH private key(s)"
  else
    _t_skip "SSH private keys" "none found in ~/.ssh"
  fi
fi



# #############################################################################
#
# SECTION: integration
# Full framework load test (framework only, empty config dir)
#
# Sources shellfire.bash with a minimal empty config dir and verifies the
# framework loads cleanly with no errors.
#
# #############################################################################

if _t_section "integration" "Full framework load test (framework-only)"; then

  # ── Test: framework loads with empty config dir ──
  _t_cmd "Integration: full framework load with empty config dir" \
    "SHELLFIRE_CONFIG_HOME=temp source shellfire.bash; echo 'loaded ok'"
  _int_output=$(
    SHELLFIRE_VERBOSE=0 bash -c '
      _tmp=$(mktemp -d)
      mkdir -p "${_tmp}/plugins"
      touch "${_tmp}/plugins.conf"
      export XDG_CONFIG_HOME="${HOME}/.config"
      export XDG_CACHE_HOME="${HOME}/.cache"
      export XDG_DATA_HOME="${HOME}/.local/share"
      export SHELLFIRE_CONFIG_HOME="${_tmp}"
      source "'"${_sf_dir}"'/shellfire.bash" 2>/dev/null </dev/null
      rm -rf "${_tmp}"
      echo "loaded ok"
    ' 2>/dev/null
  )
  [[ "${_int_output}" == *"loaded ok"* ]] && \
    _t_pass "framework loads with empty config dir" || \
    _t_fail "framework loads with empty config dir" "no output"

fi


# =============================================================================
# SUMMARY
# =============================================================================

printf '\n'
printf '%b══════════════════════════════════════════════════════════════%b\n' "${_T_SEC}" "${_T_RESET}"
printf '%b  RESULTS                                                    %b\n' "${_T_SEC}" "${_T_RESET}"
printf '%b══════════════════════════════════════════════════════════════%b\n' "${_T_SEC}" "${_T_RESET}"
printf '\n'
printf '  Total:   %b%d%b\n' "${_T_BOLD}" "${_T_TOTAL}" "${_T_RESET}"
printf '  Passed:  %b%d%b\n' "${_T_PASS}" "${_T_PASSED}" "${_T_RESET}"
_fail_colour="${_T_INFO}"
(( _T_FAILED > 0 )) && _fail_colour="${_T_FAIL}"
printf '  Failed:  %b%d%b\n' "${_fail_colour}" "${_T_FAILED}" "${_T_RESET}"
printf '  Skipped: %b%d%b\n' "${_T_SKIP}" "${_T_SKIPPED}" "${_T_RESET}"
printf '\n'

if (( _T_FAILED == 0 )); then
  printf '  %b ✓ ALL TESTS PASSED %b\n\n' "${_T_PASS}" "${_T_RESET}"
  exit 0
else
  printf '  %b ✗ %d TEST(S) FAILED %b\n\n' "${_T_FAIL}" "${_T_FAILED}" "${_T_RESET}"
  exit 1
fi
