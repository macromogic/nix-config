# Daily pull-and-switch of this checkout at 07:00 Indianapolis time, hours
# after the GitHub job that updates flake.lock
# (.github/workflows/update-inputs.yml, 06:17 UTC).
{ config, lib, pkgs, ... }:

let
  cfg = config.nixConfig;
  # Called through the profile, not the store path, so the job definition
  # never changes and a switch never restarts the job that is running it.
  command = "${config.home.homeDirectory}/.nix-profile/bin/nix-config-autoupdate";
  env = {
    NIX_CONFIG_REPO = "${config.home.homeDirectory}/${cfg.repo}";
    NIX_CONFIG_NAME = cfg.name;
  };
  autoupdate = pkgs.writeShellApplication {
    name = "nix-config-autoupdate";
    runtimeInputs = with pkgs; [ coreutils curl git ];
    text = builtins.readFile ./../scripts/autoupdate.sh;
  };
in
{
  options.nixConfig = {
    name = lib.mkOption {
      type = lib.types.str;
      description = "This machine's homeConfigurations attribute.";
    };
    repo = lib.mkOption {
      type = lib.types.str;
      description = "Path of the nix-config checkout, relative to $HOME.";
    };
    autoUpdate = lib.mkEnableOption "the daily pull-and-switch" // { default = true; };
  };

  config = lib.mkIf cfg.autoUpdate {
    home.packages = [
      autoupdate
      # The same pull-and-switch by hand: output to the terminal, no Bark ping.
      (pkgs.writeShellScriptBin "nix-config-update" ''
        export NIX_CONFIG_REPO=${lib.escapeShellArg env.NIX_CONFIG_REPO}
        export NIX_CONFIG_NAME=${lib.escapeShellArg env.NIX_CONFIG_NAME}
        export AUTOUPDATE_NOTIFY=0
        exec ${lib.getExe autoupdate} "$@"
      '')
    ];

    launchd.agents.nix-config-autoupdate = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
      enable = true;
      config = {
        ProgramArguments = [ command ];
        EnvironmentVariables = env;
        # launchd only knows local time; the Mac's zone is Indianapolis.
        # Runs at the next wake if the Mac was asleep at 07:00.
        StartCalendarInterval = [{ Hour = 7; Minute = 0; }];
        StandardOutPath = "${config.home.homeDirectory}/Library/Logs/nix-config-autoupdate.log";
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/nix-config-autoupdate.log";
      };
    };

    systemd.user.services.nix-config-autoupdate = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
      Unit.Description = "Pull nix-config and switch home-manager";
      Service = {
        Type = "oneshot";
        ExecStart = command;
        Environment = lib.mapAttrsToList (k: v: "${k}=${v}") env;
        # Some hosts don't let users read their own journal.
        StandardOutput = "append:%h/.local/state/nix-config-autoupdate.log";
        StandardError = "append:%h/.local/state/nix-config-autoupdate.log";
      };
    };
    systemd.user.timers.nix-config-autoupdate = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
      Unit.Description = "Daily nix-config pull-and-switch";
      Timer = {
        OnCalendar = "*-*-* 07:00:00 America/Indiana/Indianapolis";
        Persistent = true;
      };
      Install.WantedBy = [ "timers.target" ];
    };
  };
}
