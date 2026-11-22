# Update the T3 servers over SSH: t3-update [--check] [--no-switch] [-y] [HOST...]
#
# With no HOST, uses the hosts in $T3_HOSTS (space separated; set it in
# ~/.zshrc_host, since this repository names no machines). For each host:
#   1. nix-config-update: pull nix-config and switch, so the new t3 is
#      installed (the daily timer does this too; skip with --no-switch).
#   2. Compare the running t3-server with the installed t3 (the check in
#      autoupdate.sh).
#   3. If it is outdated, ask, then `systemctl --user restart t3-server`.
#      A restart stops running agents, so it asks per host; -y answers yes.
# --check only reports each server's state and changes nothing.

usage() {
  echo "usage: t3-update [--check] [--no-switch] [-y] [HOST...]" >&2
  exit 2
}

check=0 switch=1 yes=0
hosts=()
while [[ $# -gt 0 ]]; do
  case $1 in
    --check) check=1 ;;
    --no-switch) switch=0 ;;
    -y | --yes) yes=1 ;;
    -h | --help) usage ;;
    -*) usage ;;
    *) hosts+=("$1") ;;
  esac
  shift
done
if [[ ${#hosts[@]} -eq 0 ]]; then
  read -ra hosts <<<"${T3_HOSTS:-}"
fi
if [[ ${#hosts[@]} -eq 0 ]]; then
  echo "t3-update: no hosts; pass them or set T3_HOSTS in ~/.zshrc_host" >&2
  exit 2
fi

# Runs on the host as `bash -s -- ACTION`. Non-interactive SSH has neither
# the profile on PATH nor, on some hosts, the user's systemd bus.
read -r -d '' remote <<'EOF' || true
export PATH="$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:$PATH"
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
case $1 in
  switch)
    nix-config-update
    ;;
  status)
    if [[ ! -f $HOME/.config/t3-server.env ]]; then echo disabled; exit 0; fi
    pid=$(systemctl --user show -p MainPID --value t3-server 2>/dev/null || true)
    if ! [[ $pid =~ ^[1-9][0-9]*$ ]]; then echo stopped; exit 0; fi
    installed=$(readlink -f "$HOME/.nix-profile/bin/t3")
    installed=${installed%/bin/t3}/
    if [[ $(tr '\0' ' ' <"/proc/$pid/cmdline") == *"$installed"* ]]; then
      echo current
    else
      echo outdated
    fi
    ;;
  restart)
    systemctl --user restart t3-server
    sleep 3
    systemctl --user is-active t3-server
    ;;
esac
EOF

run() { # run HOST ACTION
  ssh -o ConnectTimeout=15 "$1" bash -s -- "$2" <<<"$remote"
}

failed=()
for host in "${hosts[@]}"; do
  echo "== $host"
  if [[ $check == 0 && $switch == 1 ]]; then
    run "$host" switch || {
      echo "t3-update: $host: nix-config-update failed; not restarting" >&2
      failed+=("$host")
      continue
    }
  fi
  state=$(run "$host" status) || {
    echo "t3-update: $host: could not read the t3-server state" >&2
    failed+=("$host")
    continue
  }
  echo "t3-server: $state"
  [[ $check == 0 && $state == outdated ]] || continue

  if [[ $yes == 0 ]]; then
    read -r -p "Restart t3-server on $host? Running agents there will stop. [y/N] " answer
    [[ $answer == [yY]* ]] || {
      echo "skipped"
      continue
    }
  fi
  if run "$host" restart; then
    echo "restarted"
  else
    echo "t3-update: $host: restart failed" >&2
    failed+=("$host")
  fi
done

if [[ ${#failed[@]} -gt 0 ]]; then
  echo "t3-update: failed on: ${failed[*]}" >&2
  exit 1
fi
