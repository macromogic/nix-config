# Fast-forward this machine's nix-config checkout to origin/main and switch
# to it, then fast-forward its other checkouts (home/clones.nix). Run daily
# by a launchd agent / systemd user timer (autoupdate.nix).
# Skips when the checkout has uncommitted changes or unpushed commits; on a
# failed switch, resets the checkout so the next run retries. Notifies via
# Bark, when BARK_KEY is set in ~/.zshrc_secrets, on a failed switch or a
# failed checkout hook.

repo=${NIX_CONFIG_REPO:?} name=${NIX_CONFIG_NAME:?}
# Timers start with a bare PATH; home-manager and nix live outside it.
export PATH="$PATH:$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:/usr/local/bin:/usr/bin:/bin"

log() { printf '%s %s\n' "$(date '+%F %T')" "$*"; }

notify() {
  [[ ${AUTOUPDATE_NOTIFY:-1} == 1 && -f $HOME/.zshrc_secrets ]] || return 0
  local settings key server
  # shellcheck source=/dev/null
  settings=$(. "$HOME/.zshrc_secrets" >/dev/null 2>&1
    printf '%s\n%s' "${BARK_KEY:-}" "${BARK_SERVER:-https://api.day.app}")
  key=${settings%%$'\n'*} server=${settings#*$'\n'}
  [[ -n $key ]] || return 0
  curl -fsS -G --data-urlencode "title=$1" --data-urlencode "body=$2" \
    --data-urlencode "group=nix-config" "${server%/}/$key" >/dev/null || true
}

update_nix_config() {
  cd "$repo"
  branch=$(git symbolic-ref --short HEAD)
  if [[ $branch != main ]]; then
    log "on branch $branch, skipped"
    return 0
  fi
  if [[ -n $(git status --porcelain --untracked-files=no) ]]; then
    log "uncommitted changes, skipped"
    return 0
  fi

  # Fetch over HTTPS: the repo is public and timers have no SSH agent.
  url=$(git remote get-url origin)
  url=${url/#git@github.com:/https://github.com/}
  git fetch --quiet "$url" main
  if [[ -n $(git rev-list FETCH_HEAD..HEAD) ]]; then
    log "unpushed local commits, skipped"
    return 0
  fi

  before=$(git rev-parse HEAD)
  target=$(git rev-parse FETCH_HEAD)
  if [[ $target == "$before" ]]; then
    log "up to date at ${before:0:7}"
    return 0
  fi

  git merge --quiet --ff-only "$target"
  git update-ref refs/remotes/origin/main "$target"
  if home-manager switch --flake ".#$name"; then
    log "switched ${before:0:7} -> ${target:0:7}"
  else
    git reset --quiet --keep "$before"
    log "switch to ${target:0:7} failed; checkout reset to ${before:0:7}"
    notify "nix-config update failed on $(hostname -s)" \
      "home-manager switch to ${target:0:7} failed; checkout left at ${before:0:7}. See the autoupdate log."
    return 1
  fi
}

# A subshell outside any `||`, so errexit still applies inside it.
set +e
(update_nix_config)
status=$?
set -e
# After the switch, so a new manifest or tool is already in place.
clones=$(nix-config-clones pull 2>&1) || clones+=$'\n'$(log "clones: pull failed")
printf '%s\n' "$clones"
if failed=$(grep -E 'clones: .*(hook|pull) failed' <<<"$clones"); then
  notify "nix-config clones failed on $(hostname -s)" "$failed"
fi
exit "$status"
