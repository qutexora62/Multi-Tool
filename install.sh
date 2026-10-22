#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  Multi Tool — installer
#  Usage:  curl -sL <raw-url>/install.sh | bash
# ============================================================
set -e

REPO="qutexora62/Multi-Tool"
BRANCH="main"
RAW="https://raw.githubusercontent.com/${REPO}/${BRANCH}"

PREFIX_DIR="${PREFIX:-/data/data/com.termux/files/usr}"
MT_HOME="${PREFIX_DIR}/lib/multitool"
MT_BIN="${PREFIX_DIR}/bin/multitool"

C='\033[1;36m'; G='\033[1;32m'; Y='\033[1;33m'; R='\033[1;31m'; N='\033[0m'

echo -e "${C}"
echo "   __  __       _ _   _        _____           _"
echo "  |  \\/  |     | | | (_)      |_   _|         | |"
echo "  | \\  / |_   _| | |_ _ ______  | | ___   ___ | |"
echo "  | |\\/| | | | | | __| |______| | |/ _ \\ / _ \\| |"
echo "  | |  | | |_| | | |_| |        | | (_) | (_) | |"
echo "  |_|  |_|\\__,_|_|\\__|_|        |_|\\___/ \\___/|_|"
echo -e "${N}"
echo -e "${C}   >> Multi Tool Installer <<${N}\n"

# ---- checks ----
if [ -z "$PREFIX" ] && [ ! -d "/data/data/com.termux/files/usr" ]; then
  echo -e "${R}[✗] This tool is for Termux only.${N}"; exit 1
fi

command -v curl >/dev/null 2>&1 || { echo -e "${Y}[i] Installing curl...${N}"; pkg install -y curl >/dev/null 2>&1; }

echo -e "${C}[i]${N} Installing to: ${MT_HOME}"

# ---- clean old install ----
if [ -d "$MT_HOME" ]; then
  chmod -R 755 "$MT_HOME" 2>/dev/null || true
  rm -rf "$MT_HOME"
fi
mkdir -p "$MT_HOME/modules" "$MT_HOME/lib"

# ---- download files ----
# Use GitHub API (base64) to bypass raw CDN cache; fall back to raw.
API="https://api.github.com/repos/${REPO}/contents"
META="${PREFIX_DIR}/tmp/.mt_meta.$$"
FILES="multitool lib/common.sh modules/github.sh modules/vercel.sh modules/netlify.sh modules/supabase.sh modules/telegram.sh"

for f in $FILES; do
  mkdir -p "$MT_HOME/$(dirname "$f")"
  ok=0
  # try API first (bypasses raw CDN cache)
  if curl -fsSL -H "User-Agent: MultiTool" "${API}/${f}" -o "$META" 2>/dev/null; then
    if python3 -c "import json,base64;d=json.load(open('$META'));open('$MT_HOME/$f','wb').write(base64.b64decode(d['content']))" 2>/dev/null; then
      ok=1
    fi
  fi
  # fall back to raw
  if [ "$ok" -eq 0 ]; then
    if curl -fsSL "${RAW}/${f}" -o "$MT_HOME/${f}" 2>/dev/null; then
      ok=1
    fi
  fi
  if [ "$ok" -eq 0 ]; then
    echo -e "${R}[✗] Failed to download: ${f}${N}"; exit 1
  fi
  echo -e "${G}[✓]${N} ${f}"
done
rm -f "$META"

# ---- permissions ----
chmod 755 "$MT_HOME/multitool"
chmod 755 "$MT_HOME/lib/common.sh"
chmod 755 "$MT_HOME/modules/"*.sh
# lock source files (read+execute only, no write)
chmod 555 "$MT_HOME/multitool" "$MT_HOME/lib/common.sh" "$MT_HOME/modules/"*.sh

# ---- launcher in $PREFIX/bin ----
cat > "$MT_BIN" <<EOF
#!/data/data/com.termux/files/usr/bin/bash
exec "${MT_HOME}/multitool" "\$@"
EOF
chmod 755 "$MT_BIN"

echo ""
echo -e "${G}============================================${N}"
echo -e "${G}  ✓ Multi Tool installed successfully!${N}"
echo -e "${G}============================================${N}"
echo -e "  Run it anytime with:  ${C}multitool${N}"
echo ""
