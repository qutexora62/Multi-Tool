#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  Multi Tool — GitHub module
#  Auth (OAuth Device Flow) + Personal Access Token
#  Full control: repos, push, create, modify, delete
# ============================================================

GH_CLIENT_ID="Ov23lihMNsuGD9PGmENr"
GH_API="https://api.github.com"
GH_TOKEN_FILE="${MT_CONF}/github.token"

# ---------- token helpers ----------
gh_save_token() {
  mkdir -p "$MT_CONF"
  chmod 700 "$MT_CONF"
  printf '%s' "$1" > "$GH_TOKEN_FILE"
  chmod 600 "$GH_TOKEN_FILE"
}

gh_get_token() {
  [ -f "$GH_TOKEN_FILE" ] && cat "$GH_TOKEN_FILE" 2>/dev/null
}

gh_clear_token() { rm -f "$GH_TOKEN_FILE"; }

# ---------- browser open (Termux) ----------
gh_open_url() {
  local url="$1"
  if command -v termux-open-url >/dev/null 2>&1; then
    termux-open-url "$url" >/dev/null 2>&1 &
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$url" >/dev/null 2>&1 &
  else
    mt_warn "Browser auto-open not available. Open manually:"
  fi
  printf "\n  ${CYAN}${BOLD}%s${RESET}\n\n" "$url"
}

# ---------- verify token ----------
gh_verify() {
  local token="$1"
  local resp
  resp=$(curl -s -m 15 -H "Authorization: token ${token}" -H "User-Agent: MultiTool" "${GH_API}/user")
  local login
  login=$(printf '%s' "$resp" | python -c "import sys,json; d=json.load(sys.stdin); print(d.get('login',''))" 2>/dev/null)
  if [ -n "$login" ]; then
    echo "$login"; return 0
  fi
  return 1
}

# ---------- login guard ----------
gh_require_login() {
  local token; token=$(gh_get_token)
  if [ -z "$token" ]; then
    mt_warn "You must login first (Authentication or Personal Access Token)."
    mt_pause
    return 1
  fi
  return 0
}

# ============================================================
#  OAuth Device Flow
# ============================================================
gh_oauth() {
  mt_clear; mt_banner
  printf "  ${BOLD}${WHITE}GitHub — Authentication (OAuth)${RESET}\n"
  mt_line
  mt_info "Requesting device code..."

  local resp
  resp=$(curl -s -m 20 -X POST \
    -H "Accept: application/json" \
    -H "User-Agent: MultiTool" \
    -d "client_id=${GH_CLIENT_ID}&scope=repo,user,delete_repo,workflow,admin:org,admin:public_key,gist" \
    "https://github.com/login/device/code")

  local device_code user_code verify_uri verify_full interval
  device_code=$(printf '%s' "$resp" | python -c "import sys,json; print(json.load(sys.stdin).get('device_code',''))" 2>/dev/null)
  user_code=$(printf '%s' "$resp" | python -c "import sys,json; print(json.load(sys.stdin).get('user_code',''))" 2>/dev/null)
  verify_uri=$(printf '%s' "$resp" | python -c "import sys,json; print(json.load(sys.stdin).get('verification_uri',''))" 2>/dev/null)
  verify_full=$(printf '%s' "$resp" | python -c "import sys,json; print(json.load(sys.stdin).get('verification_uri_complete',''))" 2>/dev/null)
  interval=$(printf '%s' "$resp" | python -c "import sys,json; print(json.load(sys.stdin).get('interval',5))" 2>/dev/null)

  if [ -z "$device_code" ]; then
    mt_err "Failed to get device code."
    printf "${DIM}%s${RESET}\n" "$resp"
    mt_pause; return
  fi

  echo ""
  printf "  ${GREEN}${BOLD}Your code:${RESET}  ${YELLOW}${BOLD}%s${RESET}\n\n" "$user_code"
  mt_info "Opening browser + showing URL..."
  # Prefer the complete URL (auto-fills the code) when available
  if [ -n "$verify_full" ]; then
    gh_open_url "$verify_full"
  else
    gh_open_url "$verify_uri"
  fi

  printf "  ${DIM}Waiting for authorization...${RESET}\n"
  local token=""
  while true; do
    sleep "${interval:-5}"
    local poll
    poll=$(curl -s -m 20 -X POST \
      -H "Accept: application/json" \
      -H "User-Agent: MultiTool" \
      -d "client_id=${GH_CLIENT_ID}&device_code=${device_code}&grant_type=urn:ietf:params:oauth:grant-type:device_code" \
      "https://github.com/login/oauth/access_token")
    token=$(printf '%s' "$poll" | python -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null)
    local err=$(printf '%s' "$poll" | python -c "import sys,json; print(json.load(sys.stdin).get('error',''))" 2>/dev/null)
    [ -n "$token" ] && break
    if [ "$err" = "authorization_pending" ]; then
      printf "."
      continue
    elif [ "$err" = "slow_down" ]; then
      interval=$((interval + 5)); continue
    elif [ -n "$err" ]; then
      printf "\n"; mt_err "OAuth error: $err"; mt_pause; return
    fi
  done

  printf "\n"
  local login
  login=$(gh_verify "$token")
  if [ -n "$login" ]; then
    gh_save_token "$token"
    mt_ok "Logged in as ${BOLD}${login}${RESET}"
    mt_ok "Token saved securely."
  else
    mt_err "Token verification failed."
  fi
  mt_pause
}

# ============================================================
#  Personal Access Token
# ============================================================
gh_pat() {
  mt_clear; mt_banner
  printf "  ${BOLD}${WHITE}GitHub — Personal Access Token${RESET}\n"
  mt_line
  mt_info "Opening the token creation page..."
  gh_open_url "https://github.com/settings/tokens/new?scopes=repo,user,delete_repo,workflow,admin:org,admin:public_key,gist&description=MultiTool"

  printf "  ${DIM}Paste your token below (input hidden):${RESET}\n  ${CYAN}>${RESET} "
  local token
  read -rs token
  printf "\n"
  [ -z "$token" ] && { mt_err "No token entered."; mt_pause; return; }

  local login
  login=$(gh_verify "$token")
  if [ -n "$login" ]; then
    gh_save_token "$token"
    mt_ok "Logged in as ${BOLD}${login}${RESET}"
    mt_ok "Token saved securely."
  else
    mt_err "Invalid token."
  fi
  mt_pause
}

# ============================================================
#  Repo operations (full control)
# ============================================================
gh_api() {
  local method="$1" path="$2" data="$3"
  local token; token=$(gh_get_token)
  if [ -n "$data" ]; then
    curl -s -m 25 -X "$method" -H "Authorization: token ${token}" -H "User-Agent: MultiTool" \
      -H "Content-Type: application/json" -d "$data" "${GH_API}${path}"
  else
    curl -s -m 25 -X "$method" -H "Authorization: token ${token}" -H "User-Agent: MultiTool" "${GH_API}${path}"
  fi
}

gh_jq() { python -c "import sys,json; d=json.load(sys.stdin); print($1)" 2>/dev/null; }

gh_list_repos() {
  gh_require_login || return
  mt_clear; mt_banner
  printf "  ${BOLD}${WHITE}GitHub — List Repository${RESET}\n"; mt_line
  mt_info "Fetching repositories..."

  local resp
  resp=$(gh_api GET "/user/repos?per_page=100&sort=updated")
  local -a names=() fulls=() vis=()
  while IFS=$'\t' read -r nm full v; do
    [ -z "$nm" ] && continue
    names+=("$nm")
    fulls+=("$full")
    vis+=("$v")
  done < <(printf '%s' "$resp" | python -c "
import sys,json
try:
    d=json.load(sys.stdin)
    if isinstance(d,dict):
        sys.exit()
    for r in d:
        print(r['full_name']+'\t'+r['full_name']+'\t'+('private' if r.get('private') else 'public'))
except Exception:
    pass
")

  if [ "${#names[@]}" -eq 0 ]; then
    mt_warn "No repositories found."
    mt_pause; return
  fi

  local sel=0 n=${#names[@]} key
  local del_armed=-1          # index armed for delete (red)
  local renaming=0            # 1 while editing a name inline
  local edit_buf=""           # rename input buffer

  printf '\033[?25l' >&2
  _gh_repo_restore() { printf '\033[?25h' >&2; }
  trap '_gh_repo_restore' RETURN EXIT

  _gh_repo_draw() {
    printf '\033[H\033[J' >&2
    printf "  ${BOLD}${WHITE}GitHub — List Repository${RESET}   ${DIM}(%d repos)${RESET}\n" "$n" >&2
    mt_line >&2
    local i
    for i in "${!names[@]}"; do
      local vtag
      if [ "${vis[$i]}" = "private" ]; then
        vtag="${RED}🔒 Private${RESET}"
      else
        vtag="${GREEN}🌐 Public${RESET}"
      fi
      if [ "$renaming" -eq 1 ] && [ "$i" -eq "$sel" ]; then
        # inline editable input
        printf "  ${MAGENTA}${BOLD}▶${RESET} ${BOLD}${WHITE}[ %s${RESET}${DIM}_${RESET}${BOLD} ]${RESET}  %b\n" "$edit_buf" "$vtag" >&2
      elif [ "$i" -eq "$del_armed" ]; then
        # armed for delete → red
        printf "  ${MAGENTA}${BOLD}▶${RESET} ${RED}${BOLD}%s${RESET}  ${RED}(Ctrl+D again to delete)${RESET}\n" "${names[$i]}" >&2
      elif [ "$i" -eq "$sel" ]; then
        printf "  ${MAGENTA}${BOLD}▶${RESET} ${BOLD}%s${RESET}  %b\n" "${names[$i]}" "$vtag" >&2
      else
        printf "    %s  %b\n" "${names[$i]}" "$vtag" >&2
      fi
    done
    if [ "$renaming" -eq 1 ]; then
      printf "\n  ${DIM}type new name · Enter = save · Esc = cancel${RESET}\n" >&2
    else
      printf "\n  ${DIM}↑/↓ move   Ctrl+R rename   Ctrl+D (x2) delete   q/Esc back${RESET}\n" >&2
    fi
  }

  while true; do
    _gh_repo_draw

    if [ "$renaming" -eq 1 ]; then
      # ---- inline rename input mode ----
      IFS= read -rsn1 key
      case "$key" in
        ''|$'\n')  # Enter → save
          renaming=0
          if [ -n "$edit_buf" ] && [ "$edit_buf" != "${names[$sel]}" ]; then
            local repo="${fulls[$sel]}"
            local resp2
            resp2=$(gh_api PATCH "/repos/$repo" "{\"name\":\"$edit_buf\"}")
            local newfull; newfull=$(printf '%s' "$resp2" | gh_jq "d.get('full_name','')")
            if [ -n "$newfull" ]; then
              names[$sel]="$newfull"
              fulls[$sel]="$newfull"
            fi
          fi
          ;;
        $'\x1b')  # Esc → cancel (handle possible arrow seq)
          IFS= read -rsn2 -t 0.05 rest
          renaming=0
          ;;
        $'\x7f'|$'\b')  # backspace
          edit_buf="${edit_buf%?}"
          ;;
        *) edit_buf+="$key" ;;
      esac
      continue
    fi

    # ---- normal navigation mode ----
    IFS= read -rsn1 key
    case "$key" in
      $'\x1b')
        IFS= read -rsn2 -t 0.05 rest
        case "$rest" in
          '[A') sel=$(( (sel - 1 + n) % n )); del_armed=-1 ;;
          '[B') sel=$(( (sel + 1) % n )); del_armed=-1 ;;
          '')   _gh_repo_restore; trap - RETURN EXIT; return ;;
        esac
        ;;
      $'\x12')  # Ctrl+R → start inline rename
        renaming=1
        edit_buf="${names[$sel]}"
        del_armed=-1
        ;;
      ''|$'\n')  # Enter → open repo file manager
        _gh_repo_restore; trap - RETURN EXIT
        gh_file_manager "${fulls[$sel]}"
        return
        ;;
      $'\x04')  # Ctrl+D → arm (red); second Ctrl+D deletes
        if [ "$del_armed" -eq "$sel" ]; then
          local repo="${fulls[$sel]}"
          local resp3
          resp3=$(gh_api DELETE "/repos/$repo" "")
          if [ -z "$resp3" ]; then
            # remove from list (names + fulls + vis)
            local -a tmp=() tmpf=() tmpv=()
            local i
            for i in "${!names[@]}"; do
              if [ "$i" -ne "$sel" ]; then
                tmp+=("${names[$i]}")
                tmpf+=("${fulls[$i]}")
                tmpv+=("${vis[$i]}")
              fi
            done
            names=("${tmp[@]}")
            fulls=("${tmpf[@]}")
            vis=("${tmpv[@]}")
            n=${#names[@]}
            del_armed=-1
            [ "$n" -eq 0 ] && { _gh_repo_restore; trap - RETURN EXIT; return; }
            [ "$sel" -ge "$n" ] && sel=$(( n - 1 ))
          else
            del_armed=-1
          fi
        else
          del_armed=$sel
        fi
        ;;
      k) sel=$(( (sel - 1 + n) % n )); del_armed=-1 ;;
      j) sel=$(( (sel + 1) % n )); del_armed=-1 ;;
      q) _gh_repo_restore; trap - RETURN EXIT; return ;;
    esac
  done
}

gh_create_repo() {
  gh_require_login || return
  mt_clear; mt_banner
  printf "  ${BOLD}${WHITE}GitHub — Create Repository${RESET}\n"; mt_line
  printf "  Repo name: "; read -r name
  [ -z "$name" ] && { mt_err "Cancelled."; mt_pause; return; }
  printf "  Description (optional): "; read -r desc
  printf "  Private? (y/N): "; read -r priv
  local p="false"; [ "$priv" = "y" ] || [ "$priv" = "Y" ] && p="true"
  local resp
  resp=$(gh_api POST "/user/repos" "{\"name\":\"$name\",\"description\":\"$desc\",\"private\":$p}")
  local url; url=$(printf '%s' "$resp" | gh_jq "d.get('html_url','')")
  if [ -n "$url" ]; then mt_ok "Created: $url"; else mt_err "Failed: $(printf '%s' "$resp" | gh_jq "d.get('message','')")"; fi
  mt_pause
}

# ============================================================
#  Git operations: clone, push, commit, pull
# ============================================================
gh_git_clone() {
  gh_require_login || return
  mt_clear; mt_banner
  printf "  ${BOLD}${WHITE}GitHub — Clone Repository${RESET}\n"; mt_line
  printf "  Repo (owner/name): "; read -r repo
  [ -z "$repo" ] && { mt_err "Cancelled."; mt_pause; return; }
  local token; token=$(gh_get_token)
  printf "  ${DIM}Cloning...${RESET}\n"
  git clone "https://${token}@github.com/${repo}.git" && mt_ok "Cloned: $repo" || mt_err "Clone failed."
  mt_pause
}

# ---------- push a local folder to a repo ----------
gh_git_push() {
  gh_require_login || return
  mt_clear; mt_banner
  printf "  ${BOLD}${WHITE}GitHub — Push Repository${RESET}\n"; mt_line

  printf "  Local folder path: "; read -r dir
  [ -z "$dir" ] && { mt_err "Cancelled."; mt_pause; return; }
  [ -d "$dir" ] || { mt_err "Folder not found: $dir"; mt_pause; return; }

  printf "  Repo (owner/name): "; read -r repo
  [ -z "$repo" ] && { mt_err "Cancelled."; mt_pause; return; }

  printf "  Branch (default main): "; read -r branch
  [ -z "$branch" ] && branch="main"

  printf "  Commit message (default 'update'): "; read -r msg
  [ -z "$msg" ] && msg="update"

  local token; token=$(gh_get_token)
  local remote="https://${token}@github.com/${repo}.git"

  ( cd "$dir" || exit 1
    git init -q 2>/dev/null
    git add -A
    git -c user.name="MultiTool" -c user.email="multitool@local" commit -q -m "$msg" 2>/dev/null
    git branch -M "$branch" 2>/dev/null
    # set or update remote
    if git remote get-url origin >/dev/null 2>&1; then
      git remote set-url origin "$remote"
    else
      git remote add origin "$remote"
    fi
    printf "  ${DIM}Pushing to %s (%s)...${RESET}\n" "$repo" "$branch"
    git push -u origin "$branch" 2>&1 | tail -3
  )
  if [ "${PIPESTATUS[0]}" -eq 0 ]; then
    mt_ok "Pushed: $repo ($branch)"
  else
    mt_err "Push failed."
  fi
  mt_pause
}

gh_logout() {
  gh_clear_token
  mt_ok "Logged out — token removed."
  mt_pause
}

# ============================================================
#  GitHub main menu
# ============================================================
github_main() {
  while true; do
    mt_clear; mt_banner
    local token login status
    token=$(gh_get_token)
    if [ -n "$token" ]; then
      login=$(gh_verify "$token")
      status="${GREEN}● Logged in${RESET} ${DIM}(${login:-unknown})${RESET}"
    else
      status="${RED}● Not logged in${RESET} ${DIM}— please authenticate first${RESET}"
    fi
    printf "  ${BOLD}${WHITE}GitHub${RESET}   %b\n" "$status"
    mt_line

    local -a items=()
    if [ -n "$token" ]; then
      # logged in → repo actions only (no Auth/PAT)
      items+=("${CYAN}List Repositories${RESET}")
      items+=("${CYAN}Create Repository${RESET}")
      items+=("${CYAN}Clone Repository${RESET}")
      items+=("${CYAN}Push Repository${RESET}")
      items+=("LogOut")
      items+=("Back")
    else
      # not logged in → ONLY Auth and PAT
      items+=("${GREEN}Authentication (OAuth)${RESET}")
      items+=("${GREEN}Personal Access Token${RESET}")
    fi

    local choice
    choice=$(mt_menu "GitHub — choose action:" "${items[@]}") || return

    if [ -n "$token" ]; then
      case "$choice" in
        0) gh_list_repos ;;
        1) gh_create_repo ;;
        2) gh_git_clone ;;
        3) gh_git_push ;;
        4) gh_logout ;;
        5) return ;;
      esac
    else
      case "$choice" in
        0) gh_oauth ;;
        1) gh_pat ;;
      esac
    fi
  done
}

# ============================================================
#  REPO FILE MANAGER
#  Browse folders/files, edit with nano, rename/delete/create/replace
# ============================================================

_gh_default_branch() {
  local repo="$1"
  gh_api GET "/repos/$repo" | gh_jq "d.get('default_branch','main')"
}

_gh_list_path() {
  local repo="$1" branch="$2" path="$3"
  local url="/repos/$repo/contents"
  [ -n "$path" ] && url="${url}/${path}"
  local resp
  resp=$(gh_api GET "${url}?ref=${branch}")
  printf '%s' "$resp" | python -c "
import sys,json
try:
    d=json.load(sys.stdin)
    if isinstance(d,dict):
        sys.exit()
    dirs=[]; files=[]
    for e in d:
        if e['type']=='dir': dirs.append(e)
        else: files.append(e)
    for e in dirs+files:
        print(e['type']+'\t'+e['name']+'\t'+e['path'])
except Exception:
    pass
"
}

_gh_fetch_file() {
  local repo="$1" path="$2" out="$3"
  local resp
  resp=$(gh_api GET "/repos/$repo/contents/${path}")
  printf '%s' "$resp" | python -c "
import sys,json,base64
try:
    d=json.load(sys.stdin)
    open('$out','wb').write(base64.b64decode(d['content']))
except Exception:
    sys.exit(1)
"
}

_gh_commit_file() {
  local repo="$1" path="$2" localfile="$3" msg="$4"
  local sha
  sha=$(gh_api GET "/repos/$repo/contents/${path}" | gh_jq "d.get('sha','')")
  local content; content=$(base64 -w0 "$localfile")
  local body
  if [ -n "$sha" ]; then
    body="{\"message\":\"$msg\",\"content\":\"$content\",\"sha\":\"$sha\"}"
  else
    body="{\"message\":\"$msg\",\"content\":\"$content\"}"
  fi
  gh_api PUT "/repos/$repo/contents/${path}" "$body" | gh_jq "d.get('commit',{}).get('sha','')"
}

_gh_delete_file() {
  local repo="$1" path="$2" msg="$3"
  local sha
  sha=$(gh_api GET "/repos/$repo/contents/${path}" | gh_jq "d.get('sha','')")
  [ -z "$sha" ] && return 1
  gh_api DELETE "/repos/$repo/contents/${path}" "{\"message\":\"$msg\",\"sha\":\"$sha\"}" >/dev/null
  return 0
}

_gh_create_file() {
  local repo="$1" path="$2" msg="$3"
  local tmp; tmp=$(mktemp "${PREFIX:-/data/data/com.termux/files/usr}/tmp/ghc.XXXXXX")
  : > "$tmp"
  _gh_commit_file "$repo" "$path" "$tmp" "$msg" >/dev/null
  rm -f "$tmp"
}

gh_file_manager() {
  local repo="$1"
  local branch; branch=$(_gh_default_branch "$repo")
  local curpath=""

  local -a etype=() ename=() epath=()
  local sel=0 n=0 key
  local del_armed=-1
  local renaming=0 edit_buf=""

  printf '\033[?25l' >&2
  _gh_fm_restore() { printf '\033[?25h' >&2; }
  trap '_gh_fm_restore' RETURN EXIT

  _gh_fm_load() {
    etype=(); ename=(); epath=()
    while IFS=$'\t' read -r t nm p; do
      [ -z "$nm" ] && continue
      etype+=("$t"); ename+=("$nm"); epath+=("$p")
    done < <(_gh_list_path "$repo" "$branch" "$curpath")
    n=${#ename[@]}
    sel=0; del_armed=-1; renaming=0
  }

  _gh_fm_draw() {
    printf '\033[H\033[J' >&2
    # ---- header ----
    printf "  ${BOLD}${MAGENTA}REPO${RESET}  ${BOLD}${WHITE}%s${RESET}\n" "$repo" >&2
    if [ -n "$curpath" ]; then
      printf "  ${BOLD}${CYAN}PATH${RESET}  ${WHITE}/%s${RESET}  ${DIM}(%d items)${RESET}\n" "$curpath" "$n" >&2
    else
      printf "  ${BOLD}${CYAN}PATH${RESET}  ${WHITE}/${RESET}  ${DIM}(%d items)${RESET}\n" "$n" >&2
    fi
    mt_line >&2

    # ---- body ----
    if [ "$n" -eq 0 ]; then
      printf "\n  ${DIM}(empty folder)${RESET}\n" >&2
    fi
    local i
    for i in "${!ename[@]}"; do
      local icon
      if [ "${etype[$i]}" = "dir" ]; then icon="${CYAN}📁${RESET}"; else icon="${DIM}📄${RESET}"; fi
      if [ "$renaming" -eq 1 ] && [ "$i" -eq "$sel" ]; then
        printf "  ${MAGENTA}${BOLD}▶${RESET} %b  ${BOLD}${WHITE}[ %s${RESET}${DIM}_${RESET}${BOLD} ]${RESET}\n" "$icon" "$edit_buf" >&2
      elif [ "$i" -eq "$del_armed" ]; then
        printf "  ${MAGENTA}${BOLD}▶${RESET} %b  ${RED}${BOLD}%s${RESET}  ${RED}← Ctrl+D again to delete${RESET}\n" "$icon" "${ename[$i]}" >&2
      elif [ "$i" -eq "$sel" ]; then
        printf "  ${MAGENTA}${BOLD}▶${RESET} %b  ${BOLD}${WHITE}%s${RESET}\n" "$icon" "${ename[$i]}" >&2
      else
        printf "    %b  %s\n" "$icon" "${ename[$i]}" >&2
      fi
    done

    # ---- footer ----
    printf "\n" >&2
    mt_line >&2
    if [ "$renaming" -eq 1 ]; then
      printf "  ${DIM}type new name${RESET}   ${BOLD}Enter${RESET}${DIM} save${RESET}   ${BOLD}Esc${RESET}${DIM} cancel${RESET}\n" >&2
    else
      printf "  ${BOLD}↑/↓${RESET}${DIM} move${RESET}      ${BOLD}Enter${RESET}${DIM} open/edit${RESET}   ${BOLD}Esc${RESET}${DIM} up/back${RESET}    ${BOLD}q${RESET}${DIM} exit${RESET}\n" >&2
      printf "  ${BOLD}Ctrl+R${RESET}${DIM} rename${RESET}   ${BOLD}Ctrl+D${RESET}${DIM} delete(x2)${RESET}   ${BOLD}Ctrl+F${RESET}${DIM} new file${RESET}   ${BOLD}Alt+F${RESET}${DIM} new folder${RESET}   ${BOLD}Alt+R${RESET}${DIM} replace${RESET}\n" >&2
    fi
  }

  _gh_fm_load

  while true; do
    _gh_fm_draw

    if [ "$renaming" -eq 1 ]; then
      IFS= read -rsn1 key
      case "$key" in
        ''|$'\n')
          renaming=0
          if [ -n "$edit_buf" ] && [ "$edit_buf" != "${ename[$sel]}" ]; then
            local oldp="${epath[$sel]}"
            local newp
            if [ -n "$curpath" ]; then newp="${curpath}/${edit_buf}"; else newp="$edit_buf"; fi
            if [ "${etype[$sel]}" = "dir" ]; then
              mt_warn "Folder rename not supported via API — skipping."
            else
              local t; t=$(mktemp "${PREFIX:-/data/data/com.termux/files/usr}/tmp/ghr.XXXXXX")
              if _gh_fetch_file "$repo" "$oldp" "$t"; then
                _gh_commit_file "$repo" "$newp" "$t" "rename: $oldp -> $newp" >/dev/null
                _gh_delete_file "$repo" "$oldp" "rename: remove old $oldp" >/dev/null
              fi
              rm -f "$t"
            fi
            _gh_fm_load
          fi
          ;;
        $'\x1b')
          IFS= read -rsn2 -t 0.05 rest
          renaming=0
          ;;
        $'\x7f'|$'\b') edit_buf="${edit_buf%?}" ;;
        *) edit_buf+="$key" ;;
      esac
      continue
    fi

    IFS= read -rsn1 key
    case "$key" in
      $'\x1b')
        IFS= read -rsn1 -t 0.05 k2
        if [ -z "$k2" ]; then
          if [ -n "$curpath" ]; then
            curpath="${curpath%/*}"
            _gh_fm_load
          else
            _gh_fm_restore; trap - RETURN EXIT; return
          fi
          continue
        fi
        case "$k2" in
          'r'|'R')
            _gh_fm_restore; trap - RETURN EXIT
            _gh_fm_replace "$repo" "$curpath" "${epath[$sel]:-}"
            _gh_fm_load
            ;;
          'f'|'F')
            _gh_fm_restore; trap - RETURN EXIT
            _gh_fm_newfolder "$repo" "$curpath"
            _gh_fm_load
            ;;
          '[')
            IFS= read -rsn1 -t 0.05 k3
            case "$k3" in
              'A') sel=$(( (sel - 1 + n) % n )); del_armed=-1 ;;
              'B') sel=$(( (sel + 1) % n )); del_armed=-1 ;;
            esac
            ;;
        esac
        ;;
      ''|$'\n')
        [ "$n" -eq 0 ] && continue
        if [ "${etype[$sel]}" = "dir" ]; then
          curpath="${epath[$sel]}"
          _gh_fm_load
        else
          _gh_fm_restore; trap - RETURN EXIT
          _gh_fm_edit "$repo" "${epath[$sel]}"
          _gh_fm_load
        fi
        ;;
      $'\x12')
        renaming=1; edit_buf="${ename[$sel]}"; del_armed=-1
        ;;
      $'\x04')
        [ "$n" -eq 0 ] && continue
        if [ "$del_armed" -eq "$sel" ]; then
          if [ "${etype[$sel]}" = "dir" ]; then
            mt_warn "Folder delete not supported via API — skipping."
          else
            _gh_fm_restore; trap - RETURN EXIT
            _gh_delete_file "$repo" "${epath[$sel]}" "delete ${epath[$sel]}" && mt_ok "Deleted: ${ename[$sel]}" || mt_err "Delete failed."
            sleep 0.7
          fi
          _gh_fm_load
        else
          del_armed=$sel
        fi
        ;;
      $'\x06')
        _gh_fm_restore; trap - RETURN EXIT
        _gh_fm_newfile "$repo" "$curpath"
        _gh_fm_load
        ;;
      k) sel=$(( (sel - 1 + n) % n )); del_armed=-1 ;;
      j) sel=$(( (sel + 1) % n )); del_armed=-1 ;;
      q) _gh_fm_restore; trap - RETURN EXIT; return ;;
    esac
  done
}

_gh_fm_edit() {
  local repo="$1" path="$2"
  local tmp; tmp=$(mktemp "${PREFIX:-/data/data/com.termux/files/usr}/tmp/ghe.XXXXXX")
  if ! _gh_fetch_file "$repo" "$path" "$tmp"; then
    mt_err "Could not fetch file."
    mt_pause; rm -f "$tmp"; return
  fi
  local before; before=$(md5sum "$tmp" | awk '{print $1}')
  nano "$tmp"
  local after; after=$(md5sum "$tmp" | awk '{print $1}')
  if [ "$before" = "$after" ]; then
    mt_info "No changes."
    sleep 0.7; rm -f "$tmp"; return
  fi
  local sha
  sha=$(_gh_commit_file "$repo" "$path" "$tmp" "edit: $path")
  if [ -n "$sha" ]; then mt_ok "Committed: $path"; else mt_err "Commit failed."; fi
  sleep 0.8
  rm -f "$tmp"
}

_gh_fm_newfile() {
  local repo="$1" curpath="$2"
  printf "  New file name: "; read -r fname
  [ -z "$fname" ] && return
  local p; if [ -n "$curpath" ]; then p="${curpath}/${fname}"; else p="$fname"; fi
  if _gh_create_file "$repo" "$p" "create: $p"; then mt_ok "Created: $p"; else mt_err "Create failed."; fi
  sleep 0.8
}

_gh_fm_newfolder() {
  local repo="$1" curpath="$2"
  printf "  New folder name: "; read -r dname
  [ -z "$dname" ] && return
  local p; if [ -n "$curpath" ]; then p="${curpath}/${dname}/.gitkeep"; else p="${dname}/.gitkeep"; fi
  if _gh_create_file "$repo" "$p" "create folder: ${p%/.gitkeep}"; then mt_ok "Created folder: $dname"; else mt_err "Create failed."; fi
  sleep 0.8
}

_gh_fm_replace() {
  local repo="$1" curpath="$2" target="$3"
  [ -z "$target" ] && { mt_warn "Select a file first."; mt_pause; return; }
  printf "  Local file to upload: "; read -r lf
  [ -f "$lf" ] || { mt_err "File not found."; mt_pause; return; }
  local sha
  sha=$(_gh_commit_file "$repo" "$target" "$lf" "replace: $target")
  if [ -n "$sha" ]; then mt_ok "Replaced: $target"; else mt_err "Replace failed."; fi
  mt_pause
}

github_main
