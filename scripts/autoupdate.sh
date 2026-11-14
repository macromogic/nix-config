# Fast-forward this machine's nix-config checkout to origin/main and switch
# to it, then fast-forward its other checkouts (home/clones.nix). Run daily
# by a launchd agent / systemd user timer (autoupdate.nix).
# Skips when the checkout has uncommitted changes or unpushed commits; on a
# failed switch, resets the checkout so the next run retries. Posts to
# Discord on a failed switch, a failed checkout hook or a t3-server left on an
# old t3: through Switchboard (topic nix-config) when switchboard-notify is
# configured and the send works, else to DISCORD_WEBHOOK_NIX_CONFIG from
# ~/.zshrc_secrets.

repo=${NIX_CONFIG_REPO:?} name=${NIX_CONFIG_NAME:?}
# Timers start with a bare PATH; home-manager and nix live outside it.
export PATH="$PATH:$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:/usr/local/bin:/usr/bin:/bin"

log() { printf '%s %s\n' "$(date '+%F %T')" "$*"; }

notify() {
  [[ ${AUTOUPDATE_NOTIFY:-1} == 1 ]] || return 0
  if command -v switchboard-notify >/dev/null; then
    local status=0
    switchboard-notify -t nix-config -l "${3:-warning}" -T "$1" "$2" >/dev/null 2>&1 || status=$?
    [[ $status == 0 ]] && return 0
    # 3: not set up on this machine. Otherwise Switchboard is down or refused
    # it; either way, fall back to the webhook so the alert isn't lost.
    [[ $status == 3 ]] || log "Switchboard notification failed ($status); trying the webhook: $1"
  fi
  local webhook=
  if [[ -f $HOME/.zshrc_secrets ]]; then
    # shellcheck source=/dev/null
    webhook=$(. "$HOME/.zshrc_secrets" >/dev/null 2>&1
      printf '%s' "${DISCORD_WEBHOOK_NIX_CONFIG:-}")
  fi
  if [[ -z $webhook ]]; then
    log "DISCORD_WEBHOOK_NIX_CONFIG not set; not sent: $1"
    return 0
  fi
  # Discord rejects messages over 2000 characters.
  jq -n --arg title "$1" --arg body "$2" '{content: ("**\($title)**\n\($body)")[:2000]}' |
    curl -fsS -H 'Content-Type: application/json' --data-binary @- "$webhook" >/dev/null ||
    log "Discord notification failed: $1"
}

# A switch never restarts t3-server (t3-server.nix), so after one it may
# still run the previous t3. The installed t3 (common.nix) keeps the server
# code in its own output, so the running process names that output's path
# exactly when it is current.
t3_server_outdated() {
  local pid installed running
  pid=$(systemctl --user show -p MainPID --value t3-server 2>/dev/null) || return 1
  [[ $pid =~ ^[1-9][0-9]*$ ]] || return 1
  installed=$(readlink -f "$HOME/.nix-profile/bin/t3") || return 1
  installed=${installed%/bin/t3}/
  running=$(tr '\0' ' ' <"/proc/$pid/cmdline") || return 1
  [[ $running != *"$installed"* ]]
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
    if t3_server_outdated; then
      log "t3-server still runs the previous t3; restart it to update"
      notify "T3 update waiting on $(hostname -s)" \
        "A new t3 is installed. Restart when no agent is running: systemctl --user restart t3-server"
    fi
  else
    git reset --quiet --keep "$before"
    log "switch to ${target:0:7} failed; checkout reset to ${before:0:7}"
    notify "nix-config update failed on $(hostname -s)" \
      "home-manager switch to ${target:0:7} failed; checkout left at ${before:0:7}. See the autoupdate log." error
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
  notify "nix-config clones failed on $(hostname -s)" "$failed" error
fi
exit "$status"
