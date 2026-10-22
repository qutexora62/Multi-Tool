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
  # Fixed, stable banner — plain ASCII border so it never breaks on
  # zoom, narrow terminals, or unfonted box-drawing glyphs.
  printf '\n' >&2
  printf "${CYAN}${BOLD}" >&2
  printf '  +======================================+\n' >&2
  printf '  |          M U L T I - T O O L S        |\n' >&2
  printf '  |              Dr. @cutexora            |\n' >&2
  printf '  +======================================+\n' >&2
  printf "${RESET}" >&2
  printf "${DIM}        -------------------------------------------------${RESET}\n\n" >&2
}

mt_line() { printf "${DIM}%s${RESET}\n" "-------------------------------------------------------"; }

# ============================================================
#  LOGIN GATE
#  ----------------------------------------------------------
#  Valid credentials (change here if needed):
MT_VALID_USER="Aarav"
MT_VALID_KEY="cutexora62"
#  Auth file is obfuscated (XOR + base64) so it is NOT plain
#  readable and cannot be opened with a simple `cat`.
MT_AUTH="${MT_CONF}/.auth"
MT_XOR_KEY="MayaMultiTool#2026"

# obfuscate: XOR each byte with key, then base64
_mt_obf() {
  printf '%s' "$1" | python3 -c "
import sys,base64
k=b'MayaMultiTool#2026'
d=sys.stdin.buffer.read()
o=bytes(b^k[i%len(k)] for i,b in enumerate(d))
sys.stdout.write(base64.b64encode(o).decode())
"
}

# deobfuscate
_mt_deobf() {
  printf '%s' "$1" | python3 -c "
import sys,base64
k=b'MayaMultiTool#2026'
try:
  o=base64.b64decode(sys.stdin.buffer.read())
  sys.stdout.write(bytes(b^k[i%len(k)] for i,b in enumerate(o)).decode())
except Exception:
  pass
"
}

# returns 0 if a valid saved auth exists
mt_is_authed() {
  [ -f "$MT_AUTH" ] || return 1
  local saved
  saved=$(_mt_deobf "$(cat "$MT_AUTH" 2>/dev/null)")
  [ "$saved" = "${MT_VALID_USER}:${MT_VALID_KEY}" ]
}

# interactive login screen (2 input boxes). Loops until correct or quit.
mt_login() {
  mt_clear
  mt_banner
  printf "${BOLD}${WHITE}  Login required to use Multi-Tools${RESET}\n" >&2
  printf "${DIM}  -------------------------------------------------${RESET}\n\n" >&2

  local user key
  printf "  ${CYAN}┌──────────────────────────────────────┐${RESET}\n" >&2
  printf "  ${CYAN}│${RESET}  ${BOLD}Username${RESET}                            ${CYAN}│${RESET}\n" >&2
  printf "  ${CYAN}└──────────────────────────────────────┘${RESET}\n" >&2
  printf "   ${BOLD}> ${RESET}"
  read -r user

  printf "\n  ${CYAN}┌──────────────────────────────────────┐${RESET}\n" >&2
  printf "  ${CYAN}│${RESET}  ${BOLD}Access Key${RESET}                          ${CYAN}│${RESET}\n" >&2
  printf "  ${CYAN}└──────────────────────────────────────┘${RESET}\n" >&2
  printf "   ${BOLD}> ${RESET}"
  read -r key
  printf "\n\n"

  if [ "$user" = "$MT_VALID_USER" ] && [ "$key" = "$MT_VALID_KEY" ]; then
    mkdir -p "$MT_CONF" 2>/dev/null
    chmod 700 "$MT_CONF" 2>/dev/null
    _mt_obf "${user}:${key}" > "$MT_AUTH"
    chmod 600 "$MT_AUTH" 2>/dev/null
    mt_ok "Login successful — welcome, ${user}!"
    sleep 1
    return 0
  else
    mt_err "Invalid Username or Access Key. Try again."
    sleep 1.5
    return 1
  fi
}

# full gate: if already authed, skip; else loop login
mt_require_login() {
  mt_is_authed && return 0
  while true; do
    mt_login && return 0
  done
}


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
#  Glitch-free menu using the alternate screen buffer.
#  The BANNER is drawn INSIDE the alt-screen (below), so it is
#  always visible together with the menu — never wiped out.
#
#  Output protocol:
#    - all drawing  -> STDERR  (visible to user)
#    - selected idx -> STDOUT  (captured by caller via $(...))
#  Returns 1 if cancelled (q / Esc).
# ============================================================
_mt_banner_lines() {
  # plain ASCII banner, safe everywhere
  printf "${CYAN}${BOLD}" >&2
  printf '  +======================================+\n' >&2
  printf '  |          M U L T I - T O O L S        |\n' >&2
  printf '  |              Dr. @cutexora            |\n' >&2
  printf '  +======================================+\n' >&2
  printf "${RESET}" >&2
  printf "${DIM}        -------------------------------------------------${RESET}\n\n" >&2
}

mt_menu() {
  local title="$1"; shift
  local -a opts=("$@")
  local n=${#opts[@]}
  local sel=0
  local key

  # enter alternate screen + hide cursor
  printf '\033[?1049h' >&2
  printf '\033[?25l' >&2
  _mt_menu_restore() {
    printf '\033[?25h' >&2
    printf '\033[?1049l' >&2
  }
  trap '_mt_menu_restore' RETURN EXIT

  _mt_draw() {
    # home + clear, then banner + menu
    printf '\033[H\033[J' >&2
    _mt_banner_lines
    printf "${BOLD}${WHITE}%s${RESET}\n" "$title" >&2
    printf "${DIM}%s${RESET}\n" "-------------------------------------------------------" >&2
    local i
    for i in "${!opts[@]}"; do
      if [ "$i" -eq "$sel" ]; then
        printf "  ${MAGENTA}${BOLD}▶${RESET} ${BOLD}%b${RESET}\n" "${opts[$i]}" >&2
      else
        printf "    %b\n" "${opts[$i]}" >&2
      fi
    done
  }

  while true; do
    _mt_draw
    IFS= read -rsn1 key
    case "$key" in
      $'\x1b')
        IFS= read -rsn2 -t 0.05 rest
        case "$rest" in
          '[A') sel=$(( (sel - 1 + n) % n )) ;;  # up
          '[B') sel=$(( (sel + 1) % n )) ;;      # down
          '')   _mt_menu_restore; trap - RETURN EXIT; return 1 ;;  # Esc
        esac
        ;;
      ''|$'\n')  # Enter
        _mt_menu_restore; trap - RETURN EXIT
        echo "$sel"
        return 0
        ;;
      k) sel=$(( (sel - 1 + n) % n )) ;;
      j) sel=$(( (sel + 1) % n )) ;;
      q) _mt_menu_restore; trap - RETURN EXIT; return 1 ;;
    esac
  done
}
