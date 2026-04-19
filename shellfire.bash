#!/usr/bin/env bash
# =============================================================================
# shellfire.bash -- Shellfire: modular bash configuration framework
# =============================================================================
#
# What this module does:
#   This is the top-level entry point sourced by ~/.bash_profile.  It:
#     1. Records the start time for load-time measurement
#     2. Sets global variables used by all other modules
#     3. Sources the shared library files from lib/
#     4. Sources all numbered core modules from core/
#     5. Reads plugins.conf and sources enabled plugins from plugins/
#     6. Renders the Shellfire startup banner (when verbose >= 1)
#
# Dependencies:
#   XDG_CONFIG_HOME   Must be set before this file is sourced (done in
#                     ~/.bash_profile)
#   SHELLFIRE_CONFIG_HOME  Optional override for the user config directory
#                          (defaults to ${XDG_CONFIG_HOME}/shellfire)
#
# Exports (global variables):
#   __shellfire_os              Operating system name (e.g. "Darwin")
#   __shellfire_verbose         Verbosity: 0=silent, 1=banner, 2=trace
#   __shellfire_hostname        Full short hostname (hostname -s)
#   __shellfire_short_hostname  Abbreviated hostname (max 5 characters)
#   __shellfire_start_time      EPOCHREALTIME at framework init
#   __shellfire_core_modules    Array of loaded core module filenames
#   __shellfire_plugin_modules  Array of loaded plugin filenames
#   __shellfire_home            Path to the framework installation directory (auto-detected)
#   __shellfire_config_home     Path to the user config directory (~/.config/shellfire)
#
# Load order:
#   lib/colours.bash -> lib/logging.bash -> lib/banner.bash
#   -> core/[0-9][0-9]_*.bash (sorted)
#   -> plugins/<name>.bash (in plugins.conf order)
#   -> banner render
#
# =============================================================================

# ---------------------------------------------------------------------------
# Startup timer
#
# $EPOCHREALTIME is available in bash 5.0+.  We capture it immediately
# so the banner can report total framework load time.
# ---------------------------------------------------------------------------

__shellfire_start_time="${EPOCHREALTIME:-}"

# ---------------------------------------------------------------------------
# Framework home — derived from the location of this script.
#
# We use BASH_SOURCE[0] so this resolves correctly regardless of how
# shellfire.bash is sourced (direct path, via .bash_profile, or from
# shellfire-dev's --init-file invocation).  realpath is used to resolve
 # symlinks so that ~/.local/share/shellfire/ → ~/code/shellfire/ works transparently.
# ---------------------------------------------------------------------------
__shellfire_home="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"

# ---------------------------------------------------------------------------
# Config home — where the user's plugins.conf, plugins/, and conf.d/ live.
#
# Defaults to the XDG-compliant ~/.config/shellfire/.
# Override with SHELLFIRE_CONFIG_HOME for testing or shellfire-dev.
# ---------------------------------------------------------------------------
__shellfire_config_home="${SHELLFIRE_CONFIG_HOME:-${XDG_CONFIG_HOME}/shellfire}"

# ---------------------------------------------------------------------------
# Global variables available to all modules
# ---------------------------------------------------------------------------

__shellfire_os="$(uname -s)"
export __shellfire_os

# Verbosity levels:
#   0 = completely silent startup (no banner, no debug output)
#   1 = show the Shellfire startup banner after all modules load
#   2 = banner + per-line _log_debug / _log_section trace output
#
# Can be overridden by setting SHELLFIRE_VERBOSE in the environment before
# opening a new shell:
#   export SHELLFIRE_VERBOSE=2
__shellfire_verbose="${SHELLFIRE_VERBOSE:-1}"
export __shellfire_verbose

# ---------------------------------------------------------------------------
# Hostname detection
# ---------------------------------------------------------------------------

__shellfire_hostname="$(hostname -s)"
export __shellfire_hostname

# _get_short_hostname -- Produce an abbreviated hostname (max 5 characters).
#
# The logic:
#   - If the hostname is already 5 chars or fewer, use it as-is.
#   - If the hostname ends with a digit, keep the first 4 chars plus the
#     trailing digit (so "macbook1" becomes "macb1").
#   - If the second-to-last character is a digit, keep the first 3 chars
#     plus the trailing 2 characters.
#   - Otherwise, take the first 5 characters.
#
# This exists purely for compact display in prompts and logs.

_get_short_hostname() {
  local hostname_length="${#__shellfire_hostname}"

  if (( hostname_length < 6 )); then
    echo "${__shellfire_hostname}"
    return
  fi

  local last_char="${__shellfire_hostname:$(( hostname_length - 1 )):1}"
  local second_last_char="${__shellfire_hostname:$(( hostname_length - 2 )):1}"

  if (( last_char > 0 )) 2>/dev/null; then
    echo "${__shellfire_hostname:0:4}${last_char}"
  elif (( second_last_char > 0 )) 2>/dev/null; then
    echo "${__shellfire_hostname:0:3}${__shellfire_hostname:$(( hostname_length - 2 ))}"
  else
    echo "${__shellfire_hostname:0:5}"
  fi
}

__shellfire_short_hostname="$(_get_short_hostname)"
export __shellfire_short_hostname

# ---------------------------------------------------------------------------
# Source shared libraries
#
# These are sourced explicitly in a fixed order (not via a glob) so that
# their functions are available to every module.  The lib/ directory uses
# plain filenames (no numeric prefix) and is not picked up by module globs.
#
# Order matters:
#   1. colours.bash  -- defines __colours (needed by logging.bash)
#   2. logging.bash  -- defines _printf, _log_*, _status_set (needed by all)
#   3. banner.bash   -- defines _banner_render (called at the end)
# ---------------------------------------------------------------------------

# shellcheck disable=SC1091
source "${__shellfire_home}/lib/colours.bash"
# shellcheck disable=SC1091
source "${__shellfire_home}/lib/logging.bash"
# shellcheck disable=SC1091
source "${__shellfire_home}/lib/banner.bash"

# ---------------------------------------------------------------------------
# Source core modules
#
# Core modules live in core/ and match [0-9][0-9]_*.bash.  They are
# always loaded, in lexicographic (i.e. numeric) order.  These provide
# the fundamental shell environment: history, PATH, environment vars,
# completions, and SSH agent.
#
# Module filenames are collected into __shellfire_core_modules so the
# banner can display them.
# ---------------------------------------------------------------------------

__shellfire_core_modules=()

for _sf_module in "${__shellfire_home}"/core/[0-9][0-9]_*.bash; do
  if [[ -f "${_sf_module}" ]]; then
    local_filename="${_sf_module##*/}"
    __shellfire_core_modules+=("${local_filename}")
    __shellfire_current_file="${local_filename}"
    _log_section "core/${local_filename}"
    # shellcheck disable=SC1090
    source "${_sf_module}"
  fi
done

unset _sf_module local_filename

# ---------------------------------------------------------------------------
# Source plugins
#
# Plugins live in plugins/ and are loaded in the order they appear in
# plugins.conf.  To disable a plugin, comment out its line with #.
# To change load order, reorder the lines.
#
# Each line in plugins.conf is the plugin name (without .bash extension
# and without the plugins/ path).  The loader looks for:
#   plugins/<name>.bash
#
# If the file doesn't exist, a warning is logged and the plugin is skipped.
# ---------------------------------------------------------------------------

__shellfire_plugin_modules=()
__shellfire_external_modules=()
_sf_plugins_conf="${__shellfire_config_home}/plugins.conf"

if [[ -f "${_sf_plugins_conf}" ]]; then
  while IFS= read -r _sf_line || [[ -n "${_sf_line}" ]]; do
    # Skip empty lines and comments
    [[ -z "${_sf_line}" || "${_sf_line}" =~ ^[[:space:]]*# ]] && continue

    # Strip leading/trailing whitespace
    _sf_plugin_name="${_sf_line##*( )}"
    _sf_plugin_name="${_sf_plugin_name%%*( )}"

    # @name entries are external modules installed outside the config layer.
    # Resolution order:
    #   1. ${NAME_HOME}/name.bash  — if NAME_HOME env var is set (e.g. SPARKS_HOME)
    #   2. ${XDG_DATA_HOME}/name/name.bash  — default XDG install location
    if [[ "${_sf_plugin_name}" == @* ]]; then
      _sf_ext_name="${_sf_plugin_name:1}"                                    # "sparks"
      _sf_ext_home_var="${_sf_ext_name^^}_HOME"                              # "SPARKS_HOME"
      _sf_ext_home="${!_sf_ext_home_var:-${XDG_DATA_HOME:-${HOME}/.local/share}/${_sf_ext_name}}"
      _sf_plugin_file="${_sf_ext_home}/${_sf_ext_name}.bash"

      if [[ -f "${_sf_plugin_file}" ]]; then
        __shellfire_external_modules+=("@${_sf_ext_name}")
        __shellfire_current_file="@${_sf_ext_name}"
        _log_section "@${_sf_ext_name}"
        # shellcheck disable=SC1090
        source "${_sf_plugin_file}"
      else
        _log_warn "External module not found: ${_sf_plugin_file}"
        _log_info "Install: git clone git@github.com:lucienboland/${_sf_ext_name}.git ${_sf_ext_home}"
      fi
    else
      _sf_plugin_file="${__shellfire_config_home}/plugins/${_sf_plugin_name}.bash"

      if [[ -f "${_sf_plugin_file}" ]]; then
        local_filename="${_sf_plugin_name}.bash"
        __shellfire_plugin_modules+=("${local_filename}")
        __shellfire_current_file="${local_filename}"
        _log_section "plugins/${local_filename}"
        # shellcheck disable=SC1090
        source "${_sf_plugin_file}"
      else
        _log_warn "Plugin not found: ${_sf_plugin_file}"
      fi
    fi
  done < "${_sf_plugins_conf}"
else
  _log_warn "plugins.conf not found at ${_sf_plugins_conf} -- no plugins loaded"
fi

unset _sf_line _sf_plugin_name _sf_plugin_file _sf_plugins_conf local_filename
unset _sf_ext_name _sf_ext_home_var _sf_ext_home
unset __shellfire_current_file

# ---------------------------------------------------------------------------
# Render the startup banner
#
# Only rendered when:
#   - __shellfire_verbose >= 1 (not silent mode)
#   - stdout is a terminal (not a pipe or script)
#
# The banner is rendered all at once AFTER every module has loaded, so it
# does not interleave with per-module trace output.
# ---------------------------------------------------------------------------

if (( __shellfire_verbose >= 1 )) && [[ -t 1 ]]; then
  _banner_render
fi
