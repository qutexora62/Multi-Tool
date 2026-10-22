#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  Multi Tool — common library
#  colors + helpers + glitch-free arrow-key menu
# ============================================================

# ---------- colors ----------
RESET='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
MAGENTA='\033[1;35m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'

# ---------- paths ----------
MT_HOME="${PREFIX:-/data/data/com.termux/files/usr}/lib/multitool"
MT_BIN="${PREFIX:-/data/data/com.termux/files/usr}/bin/multitool"
MT_CONF="${HOME}/.config/multitool"

# ---------- basic helpers ----------
mt_clear() { printf '\033[H\033[2J'; }

mt_banner() {
  local bfile="$MT_HOME/banner.txt"
  [ -f "$bfile" ] || bfile="$(dirname "$0")/banner.txt"
  printf "${CYAN}${BOLD}"
  cat "$bfile" 2>/dev/null
  printf "${RESET}"
  printf "${MAGENTA}${BOLD}        >> Multi Tool — All-in-One Manager <<${RESET}\n"
  printf "${DIM}        -------------------------------------------------${RESET}\n\n"
}

mt_line() { printf "${DIM}%s${RESET}\n" "-------------------------------------------------------"; }

mt_ok()   { printf "${GREEN}[✓]${RESET} %s\n" "$*"; }
mt_info() { printf "${CYAN}[i]${RESET} %s\n" "$*"; }
mt_warn() { printf "${YELLOW}[!]${RESET} %s\n" "$*"; }
mt_err()  { printf "${RED}[✗]${RESET} %s\n" "$*"; }

mt_pause() {
  printf "\n${DIM}Press Enter to continue...${RESET}"
  read -r _
}

# ---------- module loader ----------
mt_load() {
  local mod="$MT_HOME/modules/$1.sh"
  [ -f "$mod" ] || mod="$(dirname "$0")/modules/$1.sh"
  if [ -f "$mod" ]; then
    # shellcheck disable=SC1090
    source "$mod"
  else
    mt_err "Module not found: $1"
    return 1
  fi
}

# ============================================================
#  mt_menu <title> <option1> <option2> ...
#  ----------------------------------------------------------
#  Approach: render the WHOLE menu fresh on every keypress,
#  always starting from the SAME anchor. No cursor-up guessing,
#  no partial repaint, no scroll interference.
#
#  To keep it flicker-free we:
#    * move to a saved anchor position (cursor save/restore)
#    * clear from anchor to end of screen
#    * redraw the whole block
#
#  Output protocol:
#    - all drawing  -> STDERR  (visible to user)
#    - selected idx -> STDOUT  (captured by caller via $(...))
#  Returns 1 if cancelled (q / Esc).
# ============================================================
mt_menu() {
  local title="$1"; shift
  local -a opts=("$@")
  local n=${#opts[@]}
  local sel=0
  local key
  local -a lines

  # hide cursor
  printf '\033[?25l' >&2
  _mt_menu_restore() { printf '\033[?25h' >&2; }
  trap '_mt_menu_restore' RETURN EXIT

  # Build the full block as an array of printable lines
  _mt_build() {
    lines=()
    lines+=("${BOLD}${WHITE}${title}${RESET}")
    lines+=("${DIM}-------------------------------------------------------${RESET}")
    local i
    for i in "${!opts[@]}"; do
      if [ "$i" -eq "$sel" ]; then
        lines+=("${MAGENTA}${BOLD}  ▶ ${opts[$i]}${RESET}")
      else
        lines+=("    ${DIM}${opts[$i]}${RESET}")
      fi
    done
  }

  # Print the whole block once to establish it on screen
  _mt_build
  local i
  for i in "${!lines[@]}"; do
    printf '%b\n' "${lines[$i]}" >&2
  done

  # From now on, redraw from the first line of the block each time.
  # total lines = n + 2
  local total=$((n + 2))

  while true; do
    IFS= read -rsn1 key
    local redraw=0
    case "$key" in
      $'\x1b')
        IFS= read -rsn2 -t 0.05 rest
        case "$rest" in
          '[A') sel=$(( (sel - 1 + n) % n )); redraw=1 ;;  # up
          '[B') sel=$(( (sel + 1) % n )); redraw=1 ;;      # down
          '')   _mt_menu_restore; trap - RETURN EXIT; return 1 ;;
        esac
        ;;
      ''|$'\n')
        _mt_menu_restore; trap - RETURN EXIT
        printf '\033[%dA\033[J' "$total" >&2
        echo "$sel"
        return 0
        ;;
      k) sel=$(( (sel - 1 + n) % n )); redraw=1 ;;
      j) sel=$(( (sel + 1) % n )); redraw=1 ;;
      q) _mt_menu_restore; trap - RETURN EXIT; return 1 ;;
    esac

    if [ "$redraw" -eq 1 ]; then
      # move up to the top of the block, clear it, and redraw
      printf '\033[%dA\033[J' "$total" >&2
      _mt_build
      for i in "${!lines[@]}"; do
        printf '%b\n' "${lines[$i]}" >&2
      done
    fi
  done
}
