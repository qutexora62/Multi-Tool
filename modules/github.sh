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
  local -a names=()
  while IFS= read -r nm; do
    [ -z "$nm" ] && continue
    names+=("$nm")
  done < <(printf '%s' "$resp" | python -c "
import sys,json
try:
    d=json.load(sys.stdin)
    if isinstance(d,dict):
        sys.exit()
    for r in d:
        print(r['full_name'])
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
      if [ "$renaming" -eq 1 ] && [ "$i" -eq "$sel" ]; then
        # inline editable input
        printf "  ${MAGENTA}${BOLD}▶${RESET} ${BOLD}${WHITE}[ %s${RESET}${DIM}_${RESET}${BOLD} ]${RESET}\n" "$edit_buf" >&2
      elif [ "$i" -eq "$del_armed" ]; then
        # armed for delete → red
        printf "  ${MAGENTA}${BOLD}▶${RESET} ${RED}${BOLD}%s${RESET}  ${RED}(Ctrl+D again to delete)${RESET}\n" "${names[$i]}" >&2
      elif [ "$i" -eq "$sel" ]; then
        printf "  ${MAGENTA}${BOLD}▶${RESET} ${BOLD}%s${RESET}\n" "${names[$i]}" >&2
      else
        printf "    %s\n" "${names[$i]}" >&2
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
            local repo="${names[$sel]}"
            local resp2
            resp2=$(gh_api PATCH "/repos/$repo" "{\"name\":\"$edit_buf\"}")
            local newfull; newfull=$(printf '%s' "$resp2" | gh_jq "d.get('full_name','')")
            if [ -n "$newfull" ]; then
              names[$sel]="$newfull"
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
      $'\x04')  # Ctrl+D → arm (red); second Ctrl+D deletes
        if [ "$del_armed" -eq "$sel" ]; then
          local repo="${names[$sel]}"
          local resp3
          resp3=$(gh_api DELETE "/repos/$repo" "")
          if [ -z "$resp3" ]; then
            # remove from list
            local -a tmp=()
            local i
            for i in "${!names[@]}"; do
              [ "$i" -ne "$sel" ] && tmp+=("${names[$i]}")
            done
            names=("${tmp[@]}")
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
      items+=("${CYAN}List Repository${RESET}")
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

github_main
