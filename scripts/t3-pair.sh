# Pair a T3 client with T3 servers: t3-pair LABEL [HOST...]
#
# With no HOST, pairs with the server on this machine; otherwise with each
# HOST in turn over SSH (the host's own t3-pair does the work). For each
# server it prints the pairing link and QR code (`t3 pair --tailscale`),
# waits until the client has used it, then revokes that server's older
# sessions with the same label. So a label names one client device
# (mac, iphone, ppdsa-browser ...); reuse it to re-pair that device.

usage() {
  echo "usage: t3-pair LABEL [HOST...]" >&2
  exit 2
}

[[ $# -ge 1 && $1 != -* ]] || usage
label=$1
shift
# The label goes through a remote shell; keep it to plain characters.
[[ $label =~ ^[A-Za-z0-9._-]+$ ]] || {
  echo "t3-pair: label may only contain letters, digits, '.', '_' and '-'" >&2
  exit 2
}

if [[ $# -gt 0 ]]; then
  for host in "$@"; do
    echo "== $host"
    ssh -t "$host" .nix-profile/bin/t3-pair "$label" || echo "t3-pair: $host failed" >&2
  done
  exit 0
fi

# The port the service was started with (t3-server.nix).
if [[ -f $HOME/.config/t3-server.env ]]; then
  set -a
  # shellcheck source=/dev/null
  . "$HOME/.config/t3-server.env"
  set +a
fi

sessions() {
  t3 auth session list --json |
    jq -r --arg l "$label" '.[] | select(.client.label? == $l) | .sessionId'
}

old=$(sessions)
t3 pair --tailscale --label "$label"

# The link is valid for 5 minutes.
echo "Waiting for $label to connect ..."
new=
for _ in $(seq 100); do
  new=$(comm -13 <(sort <<<"$old") <(sessions | sort))
  [[ -z $new ]] || break
  sleep 3
done
if [[ -z $new ]]; then
  echo "t3-pair: $label did not connect in time; nothing revoked" >&2
  exit 1
fi
echo "Paired $label: $new"

for id in $old; do
  t3 auth session revoke "$id" >/dev/null
  echo "Revoked older $label session $id"
done
