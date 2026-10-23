# Global agent instructions

These apply on every machine. A project's own AGENTS.md or CLAUDE.md adds to them.

## This environment is managed by Nix
Every tool in this user environment comes from Nix, declared in the
nix-config repo (github.com/macromogic/nix-config) and applied with
home-manager. Work the Nix way by default:

- Tools live in ~/.nix-profile/bin and /nix/store, not in apt or Homebrew
  locations. Find them with `command -v <cmd>`; never hard-code a path such
  as /usr/bin/<cmd> or /opt/homebrew/bin/<cmd>.
- Need a tool once: `, <cmd> args...` (comma) or
  `nix shell nixpkgs#<pkg> -c <cmd> args...`. Find which package provides a
  command with `, -p <cmd>`, or any file with `nix-locate <path>`.
- Need several tools for a while: `nix shell nixpkgs#<a> nixpkgs#<b>` for that
  shell only.
- Project with a flake.nix or shell.nix: enter it with `nix develop` or
  `nix-shell` and use its tools instead of installing anything.
- `nixpkgs#...` resolves to the same pinned nixpkgs as the rest of the
  environment, so these commands are quick and consistent across machines.
- Managed files such as ~/.zshrc, ~/.tmux.conf and this file are read-only
  links into /nix/store. Don't edit them; propose the change to nix-config.
- Machine-specific shell settings live in ~/.zshrc_host and secrets in
  ~/.zshrc_secrets. Never print, copy or commit the contents of
  ~/.zshrc_secrets.

## Git
Whether you may manage git is decided per project. By default you may not.

- Without approval, never commit or push, and don't rewrite or move history:
  no `git commit`, `push`, `commit --amend`, `rebase`, `merge`, `reset`,
  `tag`, branch deletion or force-push. Reading git state (`status`, `diff`,
  `log`, `blame`, `show`) and editing files in the working tree are fine.
- Approval comes from either:
  - the project's own AGENTS.md or CLAUDE.md, for example a line saying
    "Agents may commit" or "Agents may commit and push"; or
  - my explicit instruction in the current session, which lasts for that
    session only and covers only what I named (commit is not push).
- When the work is ready and you have no approval, stop and say so. You can
  suggest a commit message, but leave committing to me.
- Even with approval: follow the repository's commit style, never commit
  secrets, and never force-push or push to a branch I didn't name.

## Installing software
- Never install software on your own: no apt, brew, `pip install --user`,
  `npm install -g`, `cargo install`, `nix profile install`,
  `nix-env -i` or similar. If a tool is needed permanently, say so and
  suggest adding it to nix-config.
- comma's package picker needs a terminal. If `, <cmd>` reports several
  providers or fails with "Failed to open tty", pick the package from
  `, -p <cmd>` and use `nix shell nixpkgs#<pkg> -c <cmd>` instead.
- Project-local dependencies (a virtualenv, `npm install` inside the project)
  are fine when the task needs them.
