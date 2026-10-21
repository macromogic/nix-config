# Machines I sit in front of: where agents are driven from, notifications
# land, and (later) the voice/MCP bridge runs.
{ pkgs, inputs, ... }:

{
  # Lean prompt.
  home.file.".p10k.zsh".source = ./../../dotfiles/p10k-local.zsh;

  # T3 Code desktop app; same pinned version as the `t3` servers it talks to.
  home.packages = [
    inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.t3code.desktop
  ];
}
