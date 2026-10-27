# T3 Code server as a systemd user service, so sessions keep running with
# no client attached and the desktop and phone apps can share them.
#
# Opt-in per machine, since configs are shared across servers: it starts
# only where ~/.config/t3-server.env exists. That file may set
# T3CODE_PORT (default 3773) to avoid another user's server on a shared
# host; an empty file is enough otherwise. The server listens on loopback
# only; reach it over the tailnet with `t3 pair --tailscale`, which sets up
# Tailscale Serve (HTTPS, tailnet only) and prints a pairing QR code.
#
# Updates never restart it, so a daily switch can't kill running agents:
# the unit runs t3 from the profile and keeps the old process on switch.
# Pick up a new t3 with `systemctl --user restart t3-server`.
{ lib, pkgs, ... }:

lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
  systemd.user.services.t3-server = {
    Unit = {
      Description = "T3 Code server";
      ConditionPathExists = "%h/.config/t3-server.env";
      X-SwitchMethod = "keep-old";
      StartLimitIntervalSec = 300;
      StartLimitBurst = 5;
    };
    Service = {
      WorkingDirectory = "%h";
      # The server hydrates PATH from the login shell itself (so agents see
      # ~/.zshrc_host); this is only the fallback it starts from.
      Environment = [
        "PATH=%h/.nix-profile/bin:/nix/var/nix/profiles/default/bin:/usr/local/bin:/usr/bin:/bin"
        "T3CODE_HOST=127.0.0.1"
        "T3CODE_TELEMETRY_ENABLED=false"
      ];
      EnvironmentFile = "%h/.config/t3-server.env";
      ExecStart = "%h/.nix-profile/bin/t3 serve";
      # As in T3's own unit (`t3 service install`): let the server stop its
      # agents gracefully, and don't stop it when the kernel OOM-kills one.
      KillMode = "mixed";
      OOMPolicy = "continue";
      Restart = "always";
      RestartSec = 5;
      # Some hosts don't let users read their own journal.
      StandardOutput = "append:%h/.local/state/t3-server.log";
      StandardError = "append:%h/.local/state/t3-server.log";
    };
    Install.WantedBy = [ "default.target" ];
  };
}
