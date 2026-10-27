# Servers shared with other users, where I have no root: Tailscale runs
# per user, and agents are told to keep off system-wide state.
{ lib, ... }:

{
  imports = [ ./tailscale-userspace.nix ];

  home.file = lib.genAttrs (import ./../agents/targets.nix) (_: {
    # Appended to the shared agent instructions from common.nix.
    text = lib.mkAfter (builtins.readFile ./../agents/shared-server.md);
  });
}
