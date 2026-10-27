# My Windows desktop, a WSL2 Ubuntu reached over the tailnet. Tailscale
# runs system-wide there, so the userspace one from shared-server.nix
# stays off.
{ lib, ... }:

{
  home.file = lib.genAttrs (import ./../../agents/targets.nix) (_: {
    # Appended to the shared agent instructions from common.nix.
    text = lib.mkAfter (builtins.readFile ./../../agents/pc.md);
  });
}
