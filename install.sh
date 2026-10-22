#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  Multi-Tool — installer
#  Usage:  curl -s -H "Accept: application/vnd.github.raw" \
#          "https://api.github.com/repos/qutexora62/Multi-Tool/contents/install.sh" | bash
# ============================================================
set -e

REPO="qutexora62/Multi-Tool"
BRANCH="main"
RAW="https://raw.githubusercontent.com/${REPO}/${BRANCH}"

PREFIX_DIR="${PREFIX:-/data/data/com.termux/files/usr}"
MT_HOME="${PREFIX_DIR}/lib/multitool"
MT_BIN="${PREFIX_DIR}/bin/multitool"

C='\033[1;36m'; G='\033[1;32m'; Y='\033[1;33m'; R='\033[1;31m'; N='\033[0m'

# ---- animated progress bar (single line, 0 -> 100) ----
# Draws the WHOLE line each frame: "[✓] Label  [====...] 100%"
# Uses \r + \033[K so the line is redrawn in place -> never scrolls.
_anim() {
  local label="$1"
  local i width=30 filled empty bar
  for i in $(seq 0 100); do
    filled=$(( i * width / 100 ))
    empty=$(( width - filled ))
    bar=""
    [ "$filled" -gt 0 ] && bar=$(printf '%*s' "$filled" '' | sed 's/ /=/g')
    printf "\r\033[K${G}[✓]${N} %-10s [${G}%s${N}%*s] ${Y}%3d%%${N}" \
      "$label" "$bar" "$empty" "" "$i"
    sleep 0.012
  done
}

# ---- checks ----
if [ -z "$PREFIX" ] && [ ! -d "/data/data/com.termux/files/usr" ]; then
  echo -e "${R}[✗] This tool is for Termux only.${N}"; exit 1
fi

command -v curl >/dev/null 2>&1 || { echo -e "${Y}[i] Installing curl...${N}"; pkg install -y curl >/dev/null 2>&1; }

echo ""
echo -e "${C}[i]${N} Installing to: ${MT_HOME}"

# ---- clean old install ----
if [ -d "$MT_HOME" ]; then
  chmod -R 755 "$MT_HOME" 2>/dev/null || true
  rm -rf "$MT_HOME"
fi
mkdir -p "$MT_HOME/modules" "$MT_HOME/lib"

# ---- download files (with clean names + animation) ----
API="https://api.github.com/repos/${REPO}/contents"
META="${PREFIX_DIR}/tmp/.mt_meta.$$"

# friendly label | file path  (parallel arrays — no stdin consumption)
LABELS=("Multitool" "Common" "GitHub" "Vercel" "Netlify" "Supabase" "Telegram")
FILES=("multitool" "lib/common.sh" "modules/github.sh" "modules/vercel.sh" "modules/netlify.sh" "modules/supabase.sh" "modules/telegram.sh")

for idx in "${!FILES[@]}"; do
  label="${LABELS[$idx]}"
  f="${FILES[$idx]}"
  mkdir -p "$MT_HOME/$(dirname "$f")"
  ok=0
  # try API first (bypasses raw CDN cache)  — </dev/null keeps stdin free
  if curl -fsSL -H "User-Agent: MultiTool" "${API}/${f}" -o "$META" </dev/null 2>/dev/null; then
    if python3 -c "import json,base64;d=json.load(open('$META'));open('$MT_HOME/$f','wb').write(base64.b64decode(d['content']))" </dev/null 2>/dev/null; then
      ok=1
    fi
  fi
  # fall back to raw
  if [ "$ok" -eq 0 ]; then
    if curl -fsSL "${RAW}/${f}" -o "$MT_HOME/${f}" </dev/null 2>/dev/null; then
      ok=1
    fi
  fi
  if [ "$ok" -eq 0 ]; then
    echo -e "${R}[✗] Failed to download: ${label}${N}"; exit 1
  fi
  # animate the whole "[✓] Label [bar] 100%" on ONE in-place line
  _anim "$label"
  printf "\n"
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
