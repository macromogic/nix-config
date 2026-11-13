# My Mac (the local role on darwin).
{ lib, ... }:

{
  home.file = lib.genAttrs (import ./../../agents/targets.nix) (_: {
    # Appended to the shared agent instructions from common.nix.
    text = lib.mkAfter (builtins.readFile ./../../agents/mac.md);
  }) // lib.genAttrs [ ".claude/skills/ticktick-add-task" ".codex/skills/ticktick-add-task" ] (_: {
    source = ./../../agents/skills/ticktick-add-task;
  });
}
