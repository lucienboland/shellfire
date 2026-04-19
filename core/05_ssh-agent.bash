#!/usr/bin/env bash
# =============================================================================
# core/05_ssh-agent.bash -- SSH agent discovery and management
# =============================================================================
#
# What this module does:
#   Finds or starts an SSH agent so that SSH keys are available for git,
#   scp, and remote connections.
#
#   On macOS, launchd manages a system-wide ssh-agent per user.  Its socket
#   is at /private/tmp/com.apple.launchd.*/Listeners and is set as
#   SSH_AUTH_SOCK in every login session.  This is the primary agent we
#   want to reuse -- all shells share the same agent and its loaded keys.
#
#   The discovery logic:
#     1. Test the existing SSH_AUTH_SOCK if set (covers launchd and inherited)
#     2. Search the filesystem for orphaned agent sockets
#     3. Start a new agent only as a last resort
#     4. Auto-load private keys if the agent has no identities
#
#   This only runs for interactive sessions (guarded by [[ -t 0 ]]).
#
# History note:
#   A previous version skipped the macOS launchd "Listeners" socket with a
#   pattern match, which caused every new shell to spawn its own ssh-agent.
#   The launchd socket IS a fully functional agent -- _sshagent_testsocket
#   correctly validates it (exit code 0 or 1 from ssh-add means alive).
#   The skip was removed to fix agent reuse across shells.
#
# Dependencies:
#   __shellfire_os        (from shellfire.bash)
#   __shellfire_verbose   (from shellfire.bash)
#   _printf               (from lib/logging.bash)
#   _status_set           (from lib/logging.bash)
#   _sc / _sr             (from lib/logging.bash)
#
# Exports (functions):
#   sshagent_run       Find or start an SSH agent
#   sshfingerprint     Show the fingerprint of an SSH key file
#
# =============================================================================

# ---------------------------------------------------------------------------
# _sshagent_findsockets -- Locate SSH agent sockets on the filesystem
#
# On macOS, launchd places sockets under /private/tmp (com.apple.launchd.*).
# Manually started agents put sockets under /var/folders or /tmp.
# On Linux, they're typically under /tmp.
#
# Returns: one socket path per line on stdout
# ---------------------------------------------------------------------------

_sshagent_findsockets() {
  local socket_dir

  if [[ "${__shellfire_os}" == "Darwin" ]]; then
    socket_dir="/var/folders"
  else
    socket_dir="/tmp"
  fi

  find "${socket_dir}" -uid "$(id -u)" -type s -name 'agent.*' 2>/dev/null
}

# ---------------------------------------------------------------------------
# _sshagent_testsocket -- Test whether an SSH agent socket is alive
#
# Usage:   _sshagent_testsocket /path/to/socket
#
# Probes the socket by running `ssh-add -l`.  Exit codes:
#   0 = agent has keys loaded
#   1 = agent is alive but has no keys
#   2 = cannot connect to agent (dead socket)
#
# Returns:
#   0  Socket is good and an agent process is responding
#   1  Error (missing ssh-add, wrong number of arguments)
#   3  Path exists but is not a socket
#   4  Socket is dead (file exists but no agent behind it)
# ---------------------------------------------------------------------------

_sshagent_testsocket() {
  if [[ ${#} -ne 1 ]]; then
    (( __shellfire_verbose >= 2 )) && _printf red "_sshagent_testsocket expects exactly 1 argument\n"
    return 1
  fi

  local test_socket="$1"

  # Make sure ssh-add is available (it's the tool we use to probe the agent)
  if ! command -v ssh-add &>/dev/null; then
    _printf red "ssh-add is not available; cannot test socket\n"
    return 1
  fi

  # Verify the path is actually a Unix socket
  if [[ ! -S "${test_socket}" ]]; then
    (( __shellfire_verbose >= 2 )) && _printf red "error: _sshagent_testsocket %s is not a socket!\n" "${test_socket}"
    return 3
  fi

  # Probe the socket by asking the agent to list loaded keys.
  # ssh-add returns exit code 2 when it can't connect to the agent.
  # Exit code 0 (has keys) and 1 (no keys) both mean the agent is alive.
  SSH_AUTH_SOCK="${test_socket}" ssh-add -l >/dev/null 2>&1
  local probe_result=$?

  if (( probe_result == 2 )); then
    # Exit code 2 means the socket file exists but no agent is listening.
    (( __shellfire_verbose >= 2 )) && _printf red "Socket %s is dead! Deleting!\n" "${test_socket}"
    rm -f "${test_socket}"
    return 4
  fi

  # Any other exit code (0 = keys listed, 1 = no keys loaded) means the
  # agent is alive and responding.
  (( __shellfire_verbose >= 2 )) && _printf green "Found ssh-agent socket %s\n" "${test_socket}"
  return 0
}

# ---------------------------------------------------------------------------
# _sshagent_loadkeys -- Auto-load SSH private keys if agent has none
#
# Scans ~/.ssh for private key files and adds them to the agent.
# Only runs when the agent reports no identities (ssh-add -l exit code 1).
#
# Private key detection: reads the first line of each file looking for
# "PRIVATE KEY" or "OPENSSH" markers.  Skips .pub, known_hosts,
# authorized_keys, config, and directories.
#
# Returns: the number of keys successfully added
# ---------------------------------------------------------------------------

_sshagent_loadkeys() {
  local keys_added=0
  local keyfile

  for keyfile in "${HOME}"/.ssh/*; do
    # Skip non-files
    [[ -f "${keyfile}" ]] || continue

    # Skip known non-key files
    case "${keyfile}" in
      *.pub|*known_hosts*|*authorized_keys*|*config*|*.DS_Store) continue ;;
    esac

    # Verify the file looks like a private key (check first line)
    local first_line
    first_line="$(head -1 "${keyfile}" 2>/dev/null)"
    if [[ "${first_line}" == *"PRIVATE KEY"* || "${first_line}" == *"OPENSSH"* ]]; then
      # Add the key.  If the key has a passphrase and stdin is a terminal,
      # ssh-add will prompt the user interactively.  If stdin is not a
      # terminal (e.g. piped), ssh-add will fail silently -- that's fine,
      # the user can run ssh-add manually later.
      if ssh-add "${keyfile}" 2>/dev/null; then
        (( keys_added++ ))
        _log_debug "ssh-agent: loaded key ${keyfile}"
      else
        _log_debug "ssh-agent: skipped ${keyfile} (passphrase required or error)"
      fi
    fi
  done

  echo "${keys_added}"
}

# ---------------------------------------------------------------------------
# sshagent_run -- Find an existing SSH agent or start a new one
#
# Discovery order:
#   1. Test $SSH_AUTH_SOCK (if set) -- covers the macOS launchd agent,
#      inherited env vars from parent shells, and tmux session restores
#   2. Search for orphaned agent sockets on the filesystem
#   3. Start a fresh ssh-agent as a last resort
#   4. Auto-load keys if the agent has no identities
# ---------------------------------------------------------------------------

# Track what happened for the status report
_sf_ssh_action=""
_sf_ssh_detail=""

sshagent_run() {
  local agent_found=0

  # -- Step 1: Try the existing SSH_AUTH_SOCK environment variable ----------
  #
  # This is the most common case.  On macOS, launchd sets SSH_AUTH_SOCK
  # to the system agent socket (e.g. /private/tmp/com.apple.launchd.*/Listeners).
  # That socket IS a fully functional ssh-agent.  When opening a new tab
  # or tmux pane, SSH_AUTH_SOCK is inherited and points to the same agent.
  #
  # We let _sshagent_testsocket validate it -- if the agent process is
  # responding (exit code 0 or 1 from ssh-add), we use it.

  if [[ -n "${SSH_AUTH_SOCK:-}" ]]; then
    if _sshagent_testsocket "${SSH_AUTH_SOCK}"; then
      agent_found=1
      _sf_ssh_action="reused"
    else
      unset SSH_AUTH_SOCK
      unset SSH_AGENT_PID
    fi
  fi

  # -- Step 2: Search for orphaned agent sockets ----------------------------
  #
  # This handles the case where an agent is running but the current shell
  # doesn't have SSH_AUTH_SOCK set (e.g. after an env wipe).

  if (( agent_found == 0 )); then
    local candidate_socket
    for candidate_socket in $(_sshagent_findsockets); do
      if _sshagent_testsocket "${candidate_socket}"; then
        export SSH_AUTH_SOCK="${candidate_socket}"
        agent_found=1
        _sf_ssh_action="discovered"
        break
      fi
    done
  fi

  # -- Step 3: Start a new agent -------------------------------------------

  if (( agent_found == 0 )); then
    # Start a new agent, silencing the "Agent pid NNNNN" message.
    # The PID and socket are captured via eval; the stdout line is noise.
    eval "$(ssh-agent)" >/dev/null
    _sf_ssh_action="started"
  fi

  # -- Step 4: Auto-load keys if agent has no identities --------------------
  #
  # Check if the agent has any keys loaded.  If not, scan ~/.ssh for
  # private keys and add them.  This ensures the first shell session
  # after login loads keys, and subsequent shells reuse them.

  local key_count
  key_count=$(ssh-add -l 2>/dev/null | grep -c "^[0-9]" || true)

  local keys_loaded=0
  if (( key_count == 0 )); then
    keys_loaded=$(_sshagent_loadkeys)
    # Re-count after loading
    key_count=$(ssh-add -l 2>/dev/null | grep -c "^[0-9]" || true)
  fi

  # -- Build status detail string ------------------------------------------

  # Socket path (abbreviated for display)
  local sock_display="${SSH_AUTH_SOCK:-none}"
  # Shorten the macOS launchd path for readability
  if [[ "${sock_display}" == */com.apple.launchd.*/Listeners ]]; then
    sock_display="launchd"
  elif [[ "${sock_display}" == /tmp/* || "${sock_display}" == /var/folders/* ]]; then
    sock_display="${sock_display##*/}"
  fi

  local detail_parts="${_sf_ssh_action}"
  detail_parts+=" · $(_sc 75)${sock_display}$(_sr)"

  if (( key_count > 0 )); then
    detail_parts+=" · $(_sc 114)${key_count}$(_sr) key$( (( key_count != 1 )) && echo s)"
    if (( keys_loaded > 0 )); then
      detail_parts+=" (auto-loaded)"
    fi
  else
    detail_parts+=" · $(_sc 221)no keys$(_sr)"
  fi

  _sf_ssh_detail="${detail_parts}"
}

# ---------------------------------------------------------------------------
# sshfingerprint -- Show the fingerprint of an SSH key file
#
# Usage:   sshfingerprint ~/.ssh/id_ed25519.pub
# ---------------------------------------------------------------------------

sshfingerprint() {
  if [[ ${#} -ne 1 || "$1" == "-h" ]]; then
    printf "usage: sshfingerprint <keyfile>\n"
    return 2
  fi

  if ! ssh-keygen -l -E md5 -f "$1"; then
    printf "Error: ssh-keygen -l -E md5 -f %s failed.\n" "$1"
    return 2
  fi
}

# ---------------------------------------------------------------------------
# Auto-run the agent discovery for interactive sessions
# ---------------------------------------------------------------------------

if [[ -t 0 ]]; then
  sshagent_run
  _status_set "ssh-agent" "ok" "${_sf_ssh_detail}"
else
  _status_set "ssh-agent" "warn" "non-interactive session"
fi

unset _sf_ssh_action _sf_ssh_detail
