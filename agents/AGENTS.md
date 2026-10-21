# Global agent instructions

These apply on every machine. A project's own AGENTS.md or CLAUDE.md adds to them.

## Environment
- This user environment is managed by home-manager from the nix-config repo
  (github.com/macromogic/nix-config). Managed files such as ~/.zshrc,
  ~/.tmux.conf and this file are read-only links into /nix/store. Don't edit
  them; propose the change to the repo instead.
- Machine-specific shell settings live in ~/.zshrc_host and secrets in
  ~/.zshrc_secrets. Never print, copy or commit the contents of
  ~/.zshrc_secrets.

## Missing tools
- If a command isn't installed, run it once with comma: `, <cmd> args...`
  (for example `, jq .name package.json`). It fetches the package for that run
  and installs nothing.
- comma's package picker needs a terminal. If it reports several providers or
  fails with "Failed to open tty", list them with `, -p <cmd>` and run the
  right one directly: `nix shell nixpkgs#<pkg> -c <cmd> args...`.
- Never install software on your own: no apt, brew, `pip install --user`,
  `npm install -g`, `cargo install`, `nix profile install` or similar. If a
  tool is needed permanently, say so and suggest adding it to nix-config.
- Project-local dependencies (a virtualenv, `npm install` inside the project)
  are fine when the task needs them.
