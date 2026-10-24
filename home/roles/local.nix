# Machines I sit in front of: where agents are driven from, notifications
# land, and (later) the voice/MCP bridge runs.
{ lib, pkgs, inputs, ... }:

{
  # Lean prompt.
  home.file.".p10k.zsh".source = ./../../dotfiles/p10k-local.zsh;

  # T3 Code desktop app; same pinned version as the `t3` servers it talks to.
  # On macOS it comes from the Homebrew cask (t3-code) instead: the Nix app
  # is a launcher that execs a separate Electron.app, which registers with
  # LaunchServices as pid 0, so AeroSpace never sees its windows.
  home.packages = lib.optionals pkgs.stdenv.hostPlatform.isLinux [
    inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.t3code.desktop
  ];
}
