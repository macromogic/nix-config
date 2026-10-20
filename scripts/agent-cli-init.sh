# One-time install of agent CLIs via their own installers. They update
# themselves afterwards, so Nix does not track their versions.

install_claude() { curl -fsSL https://claude.ai/install.sh | bash; }
install_codex() { npm install -g --prefix "$HOME/.local" @openai/codex; }
install_opencode() { curl -fsSL https://opencode.ai/install | bash; }

for tool in claude codex opencode; do
  # Dedupe by resolved file: /bin is often a symlink to /usr/bin.
  mapfile -t found < <(type -ap "$tool" | while read -r p; do
    printf '%s\t%s\n' "$(realpath "$p")" "$p"
  done | awk -F'\t' '!seen[$1]++ { print $2 }' || true)
  if (( ${#found[@]} > 0 )); then
    echo "$tool: found ${found[0]}"
    if (( ${#found[@]} > 1 )); then
      echo "  warning: ${#found[@]} copies on PATH; only the first is used:"
      printf '    %s\n' "${found[@]}"
    fi
    continue
  fi
  read -r -p "$tool: not found. Install it now? [y/N] " ok
  if [[ $ok == [yY]* ]]; then
    "install_$tool"
  else
    echo "$tool: skipped"
  fi
done
