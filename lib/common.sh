#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  Multi Tool — common library (colors + helpers)
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

# ---------- helpers ----------
mt_clear() { clear 2>/dev/null || printf '\033[2J\033[H'; }

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
