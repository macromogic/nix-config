# Tailscale for one user on a shared Linux server, without root.
#
# tailscaled runs as a systemd user service in userspace-networking mode:
# no TUN device and no changes to the host's routes or DNS, so nothing
# changes for other users. Connections from the tailnet to this node are
# forwarded to services listening on the server's loopback (sshd, t3 ...).
# Linger keeps it running while logged out.
#
# First run, by hand: `tailscale up`, then open the printed login URL.
{ lib, pkgs, ... }:

let
  # The CLI looks for the system socket by default; point it at ours.
  tailscale = pkgs.writeShellScriptBin "tailscale" ''
    exec ${pkgs.tailscale}/bin/tailscale \
      --socket="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/tailscale/tailscaled.sock" "$@"
  '';
in
lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
  home.packages = [ tailscale ];

  systemd.user.services.tailscaled = {
    Unit.Description = "Tailscale, userspace networking, this user only";
    Service = {
      # %S = ~/.local/state, %t = $XDG_RUNTIME_DIR.
      StateDirectory = "tailscale";
      RuntimeDirectory = "tailscale";
      # --port=0: pick a free UDP port, so several users can run one each.
      # --no-logs-no-support: don't upload logs to Tailscale.
      ExecStart = lib.concatStringsSep " " [
        "${pkgs.tailscale}/bin/tailscaled"
        "--tun=userspace-networking"
        "--statedir=%S/tailscale"
        "--socket=%t/tailscale/tailscaled.sock"
        "--port=0"
        "--no-logs-no-support"
      ];
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = [ "default.target" ];
  };
}
