# Client for Switchboard, my notification hub (a separate project, not in Nix):
# `switchboard-notify` posts to my Discord, and a skill tells agents about it.
# Each machine needs SWITCHBOARD_URL and SWITCHBOARD_TOKEN in ~/.zshrc_secrets;
# the hub mints a notify-only token per machine with scripts/new_token.py.
{ lib, pkgs, ... }:

let
  skill = "switchboard-notify";
in
{
  home.packages = [
    (pkgs.writeShellApplication {
      name = "switchboard-notify";
      runtimeInputs = with pkgs; [ coreutils curl jq ];
      text = builtins.readFile ./../scripts/switchboard-notify.sh;
    })
  ];

  home.file = lib.genAttrs [ ".claude/skills/${skill}" ".codex/skills/${skill}" ] (_: {
    source = ./../agents/skills/${skill};
  });
}
