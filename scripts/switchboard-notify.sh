# Send a notification to my Discord through Switchboard (POST /notify).
#
#   switchboard-notify [-t topic | -c channel] [-l level] [-T title] [message]
#
# -t topic    one forum post per topic, opened on first use; lowercase words
#             joined by -, e.g. nix-autoupdate
# -c channel  a Switchboard webhook channel instead of a topic
# -l level    info (default), success, warning or error
# -T title    bold first line
# The message is the remaining arguments, or stdin when there are none or "-".
#
# SWITCHBOARD_URL and SWITCHBOARD_TOKEN come from the environment, else from
# ~/.zshrc_secrets. Exits 3 when they are not set, so callers can tell
# "not configured on this machine" apart from a failed send.

usage() {
  cat <<'EOF'
usage: switchboard-notify [-t topic | -c channel] [-l level] [-T title] [message]
  -t topic    forum post for this topic (lowercase-words-with-dashes)
  -c channel  a Switchboard webhook channel instead
  -l level    info (default), success, warning, error
  -T title    bold first line
Message: the remaining arguments, or stdin. Needs SWITCHBOARD_URL and
SWITCHBOARD_TOKEN in the environment or ~/.zshrc_secrets.
EOF
}

topic="" channel="" level="info" title=""
while getopts "t:c:l:T:h" opt; do
  case "$opt" in
    t) topic=$OPTARG ;;
    c) channel=$OPTARG ;;
    l) level=$OPTARG ;;
    T) title=$OPTARG ;;
    h) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done
shift $((OPTIND - 1))
if [[ $# -eq 0 || $1 == "-" ]]; then
  message=$(cat)
else
  message="$*"
fi

url=${SWITCHBOARD_URL:-} token=${SWITCHBOARD_TOKEN:-}
if [[ (-z $url || -z $token) && -f $HOME/.zshrc_secrets ]]; then
  # In a subshell, so nothing else from the secrets file leaks into this one.
  # shellcheck source=/dev/null
  url=${url:-$(. "$HOME/.zshrc_secrets" >/dev/null 2>&1; printf '%s' "${SWITCHBOARD_URL:-}")}
  # shellcheck source=/dev/null
  token=${token:-$(. "$HOME/.zshrc_secrets" >/dev/null 2>&1; printf '%s' "${SWITCHBOARD_TOKEN:-}")}
fi
if [[ -z $url || -z $token ]]; then
  echo "switchboard-notify: set SWITCHBOARD_URL and SWITCHBOARD_TOKEN (e.g. in ~/.zshrc_secrets)" >&2
  exit 3
fi

body=$(jq -n --arg m "$message" --arg t "$title" --arg l "$level" --arg topic "$topic" --arg c "$channel" '
  {message: $m, level: $l}
  + (if $t != "" then {title: $t} else {} end)
  + (if $topic != "" then {topic: $topic} else {} end)
  + (if $c != "" then {channel: $c} else {} end)')

# The token goes to curl on stdin, not in argv, where `ps` would show it.
printf 'Authorization: Bearer %s\n' "$token" |
  curl -sS --fail-with-body --max-time 30 -H @- -H 'Content-Type: application/json' \
    --data-binary "$body" "${url%/}/notify"
echo
