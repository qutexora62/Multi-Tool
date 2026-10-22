#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  Multi Tool — common library (colors + helpers + arrow menu)
# ============================================================

# Colors
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

# Tool paths
MT_HOME="${PREFIX:-/data/data/com.termux/files/usr}/lib/multitool"
MT_BIN="${PREFIX:-/data/data/com.termux/files/usr}/bin/multitool"
MT_CONF="${HOME}/.config/multitool"

# ---------- helpers ----------
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

# Load a module safely
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

# ------------------------------------------------------------
#  mt_menu <title> <option1> <option2> ...
#  Arrow-key (↑/↓) + Enter selection. Echoes chosen index (0-based).
#  Returns 1 if cancelled (q / Esc).
# ------------------------------------------------------------
mt_menu() {
  local title="$1"; shift
  local -a opts=("$@")
  local n=${#opts[@]}
  local sel=0
  local key
  local first=1

  # hide cursor
  printf '\033[?25l'
  # trap to restore cursor on exit
  trap 'printf "\033[?25h"' EXIT

  while true; do
    # render
    if [ "$first" -eq 0 ]; then
      printf '\033[%dA' "$((n + 2))" 2>/dev/null
    fi
    first=0
    printf "${BOLD}${WHITE}%s${RESET}\n" "$title"
    printf "${DIM}%s${RESET}\n" "-------------------------------------------------------"
    for i in "${!opts[@]}"; do
      if [ "$i" -eq "$sel" ]; then
        printf "${MAGENTA}${BOLD}  ▶ %s${RESET}\n" "${opts[$i]}"
      else
        printf "    ${DIM}%s${RESET}\n" "${opts[$i]}"
      fi
    done

    # read one key
    IFS= read -rsn1 key
    case "$key" in
      $'\x1b')
        # could be escape sequence
        IFS= read -rsn2 -t 0.05 rest
        case "$rest" in
          '[A') sel=$(( (sel - 1 + n) % n )) ;;   # up
          '[B') sel=$(( (sel + 1) % n )) ;;       # down
          '')   printf '\033[?25h'; trap - EXIT; return 1 ;;  # Esc
        esac
        ;;
      ''|$'\n') # Enter
        printf '\033[?25h'; trap - EXIT
        printf '\033[%dA' "$((n + 2))" 2>/dev/null
        printf '\033[J' 2>/dev/null
        echo "$sel"
        return 0
        ;;
      k) sel=$(( (sel - 1 + n) % n )) ;;
      j) sel=$(( (sel + 1) % n )) ;;
      q) printf '\033[?25h'; trap - EXIT; return 1 ;;
    esac
  done
}
