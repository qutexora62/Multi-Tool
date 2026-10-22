#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  Multi Tool — uninstaller
#  Usage:  curl -sL <raw-url>/uninstall.sh | bash
# ============================================================
PREFIX_DIR="${PREFIX:-/data/data/com.termux/files/usr}"
MT_HOME="${PREFIX_DIR}/lib/multitool"
MT_BIN="${PREFIX_DIR}/bin/multitool"
MT_CONF="${HOME}/.config/multitool"

C='\033[1;36m'; G='\033[1;32m'; Y='\033[1;33m'; N='\033[0m'

# friendly display paths (do not show the real internal path)
DISPLAY_HOME="/cutexora/termux/lib/multitool"
DISPLAY_BIN="/cutexora/termux/bin/multitool"

echo -e "${C}>> Multi Tool Uninstaller <<${N}\n"

# unlock read-only files then remove
if [ -d "$MT_HOME" ]; then
  chmod -R 755 "$MT_HOME" 2>/dev/null || true
  rm -rf "$MT_HOME"
  echo -e "${G}[✓]${N} Removed: $DISPLAY_HOME"
else
  echo -e "${Y}[i]${N} Not found: $DISPLAY_HOME"
fi

if [ -e "$MT_BIN" ]; then
  rm -f "$MT_BIN"
  echo -e "${G}[✓]${N} Removed: $DISPLAY_BIN"
fi

# remove saved config/tokens
if [ -d "$MT_CONF" ]; then
  printf "\n${Y}[?]${N} Also remove saved tokens/config (%s)? (y/N): " "$MT_CONF"
  read -r ans
  if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
    rm -rf "$MT_CONF"
    echo -e "${G}[✓]${N} Removed config: $MT_CONF"
  else
    echo -e "${Y}[i]${N} Kept config: $MT_CONF"
  fi
fi

echo ""
echo -e "${G}============================================${N}"
echo -e "${G}  ✓ Multi Tool uninstalled!${N}"
echo -e "${G}============================================${N}"
