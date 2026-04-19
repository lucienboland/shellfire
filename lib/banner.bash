#!/usr/bin/env bash
# =============================================================================
# lib/banner.bash -- Shellfire startup banner renderer
# =============================================================================
#
# What this module does:
#   Renders a rich TUI dashboard after all modules have loaded.  The banner
#   shows a flame-gradient SHELLFIRE header, system information, and a
#   status table with per-module detail.
#
#   The banner is designed to be the ONLY visible output at verbose level 1.
#   At verbose level 0 it is suppressed entirely.
#
# Design:
#   - Dynamic width: adapts to terminal width (tput cols / $COLUMNS)
#   - Minimum inner width = 41 (SHELLFIRE logo 33 + 3 pad + 5 margin)
#   - Maximum inner width = terminal_width - 2 (for the │ borders)
#   - Rounded box-drawing borders (╭╮╰╯─│├┤) in dim grey
#   - SHELLFIRE logo in 3-row half-block art with flame gradient
#     (dark red → orange → bright yellow, bottom-up)
#   - System info line: user@host · OS · bash version · module count · time
#   - Two sections: "core" and "plugins", each with status rows
#   - Status icons: ✓ (green/ok), ! (yellow/warn), ✗ (red/error)
#   - Each row shows: icon, filename, detail text
#   - Multi-line detail: newlines in detail strings produce continuation
#     lines indented below the filename column with no icon
#   - Coloured detail: ANSI escapes in detail strings are preserved for
#     display but stripped when computing visible width for alignment
#
# Dependencies:
#   __shellfire_status_state   (from lib/logging.bash)
#   __shellfire_status_detail  (from lib/logging.bash)
#   __shellfire_status_file    (from lib/logging.bash)
#   __shellfire_status_order   (from lib/logging.bash)
#   __shellfire_core_modules   (from shellfire.bash)
#   __shellfire_plugin_modules (from shellfire.bash)
#   __shellfire_external_modules (from shellfire.bash)
#   __shellfire_hostname       (from shellfire.bash)
#   __shellfire_os             (from shellfire.bash)
#   __shellfire_start_time     (from shellfire.bash)
#
# Exports (functions):
#   _banner_render    Render the complete startup banner to stdout
#
# =============================================================================

_banner_render() {
  # -- Escape sequences -----------------------------------------------------
  local R=$'\033[0m'       # reset all attributes
  local B=$'\033[1m'       # bold
  local D=$'\033[2m'       # dim

  # -- 256-colour helpers ---------------------------------------------------
  # Usage: $(_c256 N) sets foreground to 256-colour index N
  _c256() { printf '\033[38;5;%sm' "$1"; }

  # -- Colour palette -------------------------------------------------------
  #
  # Border:      dim grey (240)
  # Logo row 1:  dark red (124) -- flames at the tips
  # Logo row 2:  orange (208)   -- flames in the middle
  # Logo row 3:  bright yellow-white (221) -- hottest at the base
  # Info line:   muted teal (109)
  # Section:     bright cyan (75)
  # Status ok:   green (114)
  # Status warn: yellow (221)
  # Status err:  red-pink (204)
  # Filename:    bright white bold (252)
  # Detail:      muted grey (243)
  # Footer:      dim grey (243)

  local C_BORDER C_LOGO1 C_LOGO2 C_LOGO3 C_GREEN
  local C_INFO C_SECTION C_OK C_WARN C_ERR C_FILE C_DETAIL C_FOOTER
  C_BORDER=$(_c256 240)
  C_LOGO1=$(_c256 124)
  C_LOGO2=$(_c256 208)
  C_LOGO3=$(_c256 221)
  C_GREEN=$(_c256 46)
  C_INFO=$(_c256 109)
  C_SECTION=$(_c256 75)
  C_OK=$(_c256 114)
  C_WARN=$(_c256 221)
  C_ERR=$(_c256 204)
  C_FILE=$(_c256 252)
  C_DETAIL=$(_c256 243)
  C_FOOTER=$(_c256 243)

  # -- Layout geometry (dynamic) --------------------------------------------
  #
  # Detect terminal width from $COLUMNS (set by bash for interactive shells)
  # or fall back to tput cols.  If neither works, assume 80.
  #
  # Inner width W = space between the │ borders.
  # Total line width on screen = 1(│) + W + 1(│) = W+2.
  #
  # Minimum W: The SHELLFIRE logo (33) + gap (2) + terminal icon (7) = 42.
  # With 3-char left pad and a 5-char right margin, minimum useful W = 50.
  #
  # Maximum W: terminal_width - 2 (for the two │ border chars).
  #
  # The filename column width adapts: at W=76 it's 24 chars; it scales
  # proportionally but is clamped to [16, 28].

  local term_width="${COLUMNS:-$(tput cols 2>/dev/null || echo 80)}"
  local min_W=50
  local max_W=$(( term_width - 2 ))

  # Clamp max_W to be at least min_W (tiny terminals get horizontal scroll)
  (( max_W < min_W )) && max_W="${min_W}"

  local W="${max_W}"
  local PAD="   "    # 3-space left padding for content inside the box

  # Compute adaptive filename column width.
  # Base: 24 at W=76.  Scale linearly, clamp to [16, 28].
  local fname_width=$(( 24 * W / 76 ))
  (( fname_width < 16 )) && fname_width=16
  (( fname_width > 28 )) && fname_width=28

  # -- Drawing helpers ------------------------------------------------------

  # _hline: draw a horizontal rule of ─ characters
  # Usage: _hline <width>
  _hline() {
    local i
    for (( i = 0; i < $1; i++ )); do printf '─'; done
  }

  # _spaces: print N space characters
  # Usage: _spaces <count>
  _spaces() {
    local count=$(( $1 ))
    (( count > 0 )) && printf '%*s' "${count}" ''
  }

  # -- ANSI-stripping helper ------------------------------------------------
  # _strip_ansi: Remove ANSI escape sequences from a string.
  # Used to compute visible (display) width of strings that contain colour.
  #
  # This handles:
  #   CSI sequences: \033[ ... m  (SGR - colours, bold, reset, etc.)
  #   OSC sequences: \033] ... \007  (title setting, etc.)
  #
  # Usage: local clean=$(_strip_ansi "coloured string")
  _strip_ansi() {
    local s="$1"
    # Remove CSI sequences (e.g. \033[38;5;114m, \033[0m)
    while [[ "${s}" =~ $'\033'"["[0-9\;]*m ]]; do
      s="${s//${BASH_REMATCH[0]}/}"
    done
    echo -n "${s}"
  }

  # _visible_len: Return the visible (display) length of a string,
  # stripping ANSI escapes first.
  _visible_len() {
    local clean
    clean="$(_strip_ansi "$1")"
    echo -n "${#clean}"
  }

  # -- Flame gradient for the accent line -----------------------------------
  # A thin gradient bar using ━ (heavy horizontal) with flame colours.
  # Colours: dark red -> red -> orange -> yellow -> white
  local flame_gradient=(52 88 124 160 196 202 208 214 220 226 228 230)

  _flame_bar() {
    local width=$1
    local glen=${#flame_gradient[@]}
    local i gi
    for (( i = 0; i < width; i++ )); do
      gi=$(( i * glen / width ))
      printf '\033[38;5;%sm━' "${flame_gradient[gi]}"
    done
    printf '%b' "${R}"
  }

  # -- Status icon helper ---------------------------------------------------
  # Returns the coloured icon for a given state.  Each icon is 1 char wide.
  _status_icon() {
    case "$1" in
      ok)    printf '%b✓%b' "${C_OK}" "${R}" ;;
      warn)  printf '%b!%b' "${C_WARN}" "${R}" ;;
      error) printf '%b✗%b' "${C_ERR}" "${R}" ;;
      *)     printf '%b·%b' "${C_DETAIL}" "${R}" ;;
    esac
  }

  # -- Status row helper (multi-line and ANSI-aware) ------------------------
  #
  # Prints one or more status rows inside the box for a single module.
  #
  # Format (first line):
  #   │   ✓  filename.bash          detail text (possibly coloured)       │
  #
  # Format (continuation lines, if detail contains \n):
  #   │                             more detail text                      │
  #
  # Layout breakdown:
  #   PAD(3) + icon(1) + gap(2) + filename(fname_width) + detail + trail
  #
  # Continuation lines replace the icon+gap+filename with spaces of the
  # same width, so the detail text aligns vertically.
  #
  # ANSI escapes in detail strings are preserved for display but stripped
  # when computing visible width for alignment/truncation.

  _status_row() {
    local state="$1"
    local filename="$2"
    local detail="$3"

    # Width available for detail text on each line
    local detail_max=$(( W - 3 - 1 - 2 - fname_width ))

    # Truncate filename if needed (visible chars only, filenames don't have ANSI)
    if (( ${#filename} > fname_width )); then
      filename="${filename:0:$(( fname_width - 1 ))}…"
    fi

    # The indent prefix for continuation lines: same width as
    # PAD + icon + gap + filename columns, but all spaces.
    local indent_width=$(( 3 + 1 + 2 + fname_width ))

    # Split detail on newlines into an array
    local IFS=$'\n'
    local -a lines=()
    # shellcheck disable=SC2206
    lines=( ${detail} )
    unset IFS

    # If detail is empty, ensure we have one empty line
    (( ${#lines[@]} == 0 )) && lines=("")

    local line_idx=0
    local line visible_detail_len trail

    for line in "${lines[@]}"; do
      # Truncate this line if its visible length exceeds detail_max.
      # We must be careful to truncate at a visible-char boundary,
      # not in the middle of an ANSI escape.
      local vis_len
      vis_len=$(_visible_len "${line}")

      if (( vis_len > detail_max && detail_max > 1 )); then
        # Truncate: walk the string, counting visible chars, and cut.
        # This is necessarily character-by-character to avoid splitting escapes.
        local truncated="" vis_count=0 max_vis=$(( detail_max - 1 ))
        local ch_idx str_len=${#line}
        for (( ch_idx = 0; ch_idx < str_len; ch_idx++ )); do
          local ch="${line:ch_idx:1}"
          if [[ "${ch}" == $'\033' ]]; then
            # Start of an escape sequence — copy until 'm' (SGR terminator)
            local esc="${ch}"
            while (( ch_idx + 1 < str_len )); do
              (( ch_idx++ ))
              esc+="${line:ch_idx:1}"
              [[ "${line:ch_idx:1}" == "m" ]] && break
            done
            truncated+="${esc}"
          else
            if (( vis_count >= max_vis )); then
              break
            fi
            truncated+="${ch}"
            (( vis_count++ ))
          fi
        done
        line="${truncated}${R}…"
        vis_len=$(( max_vis + 1 ))
      fi

      if (( line_idx == 0 )); then
        # First line: icon + filename + detail
        local visible_row_len=$(( 3 + 1 + 2 + fname_width + vis_len ))
        trail=$(( W - visible_row_len ))
        (( trail < 0 )) && trail=0

        printf '%b│%b%s' "${C_BORDER}" "${R}" "${PAD}"
        _status_icon "${state}"
        printf '  %b%b%-*s%b%b%s%b' \
          "${B}" "${C_FILE}" "${fname_width}" "${filename}" "${R}" \
          "${C_DETAIL}" "${line}" "${R}"
        _spaces "${trail}"
        printf '%b│%b\n' "${C_BORDER}" "${R}"
      else
        # Continuation line: indented, no icon, no filename
        local visible_cont_len=$(( indent_width + vis_len ))
        trail=$(( W - visible_cont_len ))
        (( trail < 0 )) && trail=0

        printf '%b│%b' "${C_BORDER}" "${R}"
        _spaces "${indent_width}"
        printf '%b%s%b' "${C_DETAIL}" "${line}" "${R}"
        _spaces "${trail}"
        printf '%b│%b\n' "${C_BORDER}" "${R}"
      fi

      (( line_idx++ ))
    done
  }

  # -- Empty row helper -----------------------------------------------------
  _empty_row() {
    printf '%b│%b' "${C_BORDER}" "${R}"
    _spaces "${W}"
    printf '%b│%b\n' "${C_BORDER}" "${R}"
  }

  # -- Section divider helper -----------------------------------------------
  # Prints: ├── section ────────────────...──┤
  _section_divider() {
    local label="$1"
    local label_len=${#label}
    # Layout: ├(1) + ── (2) + space(1) + label + space(1) + ──...(remaining) + ┤(1) = W+2
    local rule_len=$(( W - 2 - 1 - label_len - 1 ))
    (( rule_len < 2 )) && rule_len=2

    printf '%b├──%b %b%b%s%b %b' \
      "${C_BORDER}" "${R}" \
      "${B}" "${C_SECTION}" "${label}" "${R}" \
      "${C_BORDER}"
    _hline "${rule_len}"
    printf '┤%b\n' "${R}"
  }

  # =========================================================================
  # RENDER THE BANNER
  # =========================================================================

  printf '\n'

  # -- Top border: ╭───────...──╮ ------------------------------------------
  printf '%b╭' "${C_BORDER}"
  _hline "${W}"
  printf '╮%b\n' "${R}"

  # -- Empty row above logo -------------------------------------------------
  _empty_row

  # -- SHELLFIRE logo (3 rows, flame gradient) ------------------------------
  #
  # Each letter is 3 chars wide, separated by 1 space.
  # S(3) H(3) E(3) L(3) L(3) F(3) I(1) R(3) E(3) = 25 chars + 8 gaps = 33
  #
  local logo1="█▀▀ █ █ █▀▀ █   █   █▀▀ █ █▀▄ █▀▀"
  local logo2="▀▀█ █▀█ █▀▀ █   █   █▀▀ █ █▀▄ █▀▀"
  local logo3="▄▄█ █ █ █▄▄ █▄▄ █▄▄ █   █ █ █ █▄▄"

  # Terminal phosphor icon (7 chars)
  local icon1="▗▄▄▄▄▄▖"
  local icon2="▐${C_GREEN}>_  ${R}${C_BORDER} ▌"
  local icon3="▝▀▀▀▀▀▘"

  # Combined width: logo(33) + gap(2) + icon(7) = 42
  local logo_trail=$(( W - 3 - 42 ))
  (( logo_trail < 0 )) && logo_trail=0

  # Logo row 1 (dark red -- flame tips)
  printf '%b│%b%s%b%s%b  %b%s%b' "${C_BORDER}" "${R}" "${PAD}" "${C_LOGO1}" "${logo1}" "${R}" "${C_BORDER}" "${icon1}" "${R}"
  _spaces "${logo_trail}"
  printf '%b│%b\n' "${C_BORDER}" "${R}"

  # Logo row 2 (orange -- flame body)
  printf '%b│%b%s%b%s%b  %b%s%b' "${C_BORDER}" "${R}" "${PAD}" "${C_LOGO2}" "${logo2}" "${R}" "${C_BORDER}" "${icon2}" "${R}"
  _spaces "${logo_trail}"
  printf '%b│%b\n' "${C_BORDER}" "${R}"

  # Logo row 3 (bright yellow -- flame base / hottest)
  printf '%b│%b%s%b%s%b  %b%s%b' "${C_BORDER}" "${R}" "${PAD}" "${C_LOGO3}" "${logo3}" "${R}" "${C_BORDER}" "${icon3}" "${R}"
  _spaces "${logo_trail}"
  printf '%b│%b\n' "${C_BORDER}" "${R}"

  # -- Empty row below logo -------------------------------------------------
  _empty_row

  # -- Flame accent bar (inside the box) ------------------------------------
  # │<flame bar across W chars>│
  printf '%b│%b' "${C_BORDER}" "${R}"
  _flame_bar "${W}"
  printf '%b│%b\n' "${C_BORDER}" "${R}"

  # -- Empty row below accent -----------------------------------------------
  _empty_row

  # -- System info line -----------------------------------------------------
  # Format: user@host · OS · bash X.Y · N modules · 0.12s
  local bash_ver="${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}"
  local total_modules=$(( ${#__shellfire_core_modules[@]} + ${#__shellfire_plugin_modules[@]} + ${#__shellfire_external_modules[@]} ))

  # Compute elapsed time
  local elapsed="?"
  if [[ -n "${__shellfire_start_time:-}" ]] && [[ -n "${EPOCHREALTIME:-}" ]]; then
    # EPOCHREALTIME is a float like "1234567890.123456"
    # Bash doesn't do float arithmetic, so we use awk.
    local end_time="${EPOCHREALTIME}"
    elapsed="$(awk "BEGIN { printf \"%.2f\", ${end_time} - ${__shellfire_start_time} }")"
  fi

  local info_text="${USER}@${__shellfire_hostname} · ${__shellfire_os} · bash ${bash_ver} · ${total_modules} modules · ${elapsed}s"
  local info_len=${#info_text}
  local info_trail=$(( W - 3 - info_len ))
  (( info_trail < 0 )) && info_trail=0

  printf '%b│%b%s%b%s%b' "${C_BORDER}" "${R}" "${PAD}" "${C_INFO}" "${info_text}" "${R}"
  _spaces "${info_trail}"
  printf '%b│%b\n' "${C_BORDER}" "${R}"

  # -- Empty row below info -------------------------------------------------
  _empty_row

  # -- Core section ---------------------------------------------------------
  _section_divider "core"
  _empty_row

  local mod
  for mod in "${__shellfire_core_modules[@]}"; do
    local mod_name="${mod%.bash}"          # strip .bash for the status key
    mod_name="${mod_name#[0-9][0-9]_}"    # strip numeric prefix for key lookup
    local state="${__shellfire_status_state[${mod_name}]:-ok}"
    local detail="${__shellfire_status_detail[${mod_name}]:-}"
    _status_row "${state}" "${mod}" "${detail}"
  done

  _empty_row

  # -- Plugins section ------------------------------------------------------
  if (( ${#__shellfire_plugin_modules[@]} > 0 )); then
    _section_divider "plugins"
    _empty_row

    for mod in "${__shellfire_plugin_modules[@]}"; do
      local mod_name="${mod%.bash}"
      local state="${__shellfire_status_state[${mod_name}]:-ok}"
      local detail="${__shellfire_status_detail[${mod_name}]:-}"
      _status_row "${state}" "${mod}" "${detail}"
    done

    _empty_row
  fi

  # -- External section (modules loaded from outside the config layer) ------
  if (( ${#__shellfire_external_modules[@]} > 0 )); then
    _section_divider "external"
    _empty_row

    for mod in "${__shellfire_external_modules[@]}"; do
      local mod_name="${mod:1}"          # strip @ prefix: "@sparks" -> "sparks"
      local state="${__shellfire_status_state[${mod_name}]:-ok}"
      local detail="${__shellfire_status_detail[${mod_name}]:-}"
      _status_row "${state}" "${mod}" "${detail}"
    done

    _empty_row
  fi

  # -- Bottom border: ╰───────...──╯ ---------------------------------------
  printf '%b╰' "${C_BORDER}"
  _hline "${W}"
  printf '╯%b\n' "${R}"

  # -- Footer line (outside the box, centred hint) --------------------------
  local hint="verbose: export SHELLFIRE_VERBOSE=2"
  local hint_len=${#hint}
  local hint_left=$(( (W + 2 - hint_len) / 2 ))
  printf '%b' "${C_FOOTER}"
  _spaces "${hint_left}"
  printf '%s' "${hint}"
  printf '%b\n\n' "${R}"

  # -- Clean up local functions ---------------------------------------------
  unset -f _c256 _hline _spaces _strip_ansi _visible_len
  unset -f _flame_bar _status_icon _status_row
  unset -f _empty_row _section_divider
}
