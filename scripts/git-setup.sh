# Interactive global git identity setup.
# Defaults come from this machine's existing ~/.gitconfig, never from the repo.

ask() {
  local prompt=$1 current=$2 reply
  if [[ -n $current ]]; then
    read -r -p "$prompt [$current]: " reply
    echo "${reply:-$current}"
  else
    read -r -p "$prompt: " reply
    echo "$reply"
  fi
}

name=$(ask "user.name" "$(git config --global user.name || true)")
email=$(ask "user.email" "$(git config --global user.email || true)")
helper=$(ask "credential.helper (blank to skip, '-' to unset)" "$(git config --global credential.helper || true)")

if [[ -z $name || -z $email ]]; then
  echo "user.name and user.email are required." >&2
  exit 1
fi

echo
echo "  user.name         = $name"
echo "  user.email        = $email"
echo "  credential.helper = ${helper:-(unchanged)}"
read -r -p "Write to ~/.gitconfig? [y/N] " ok
[[ $ok == [yY]* ]] || { echo "Aborted."; exit 1; }

git config --global user.name "$name"
git config --global user.email "$email"
if [[ $helper == "-" ]]; then
  git config --global --unset credential.helper || true
elif [[ -n $helper ]]; then
  git config --global credential.helper "$helper"
fi
echo "Done."
