# Dev servers reached over SSH: where agent sessions actually run.
{ lib, ... }:

{
  imports = [ ./../tailscale-userspace.nix ];

  home.file = {
    # Classic (filled) prompt, so a remote shell is obvious at a glance.
    ".p10k.zsh".source = ./../../dotfiles/p10k-remote.zsh;
  } // lib.genAttrs (import ./../../agents/targets.nix) (_: {
    # Appended to the shared agent instructions from common.nix.
    text = lib.mkAfter (builtins.readFile ./../../agents/remote.md);
  });

  programs.zsh.oh-my-zsh.plugins = [ "docker-compose" ];
}
