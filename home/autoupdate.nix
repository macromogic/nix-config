# Daily pull-and-switch of this checkout, a few hours after the GitHub job
# that updates flake.lock (.github/workflows/update-inputs.yml, 06:17 UTC).
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
      (pkgs.writeShellApplication {
        name = "nix-config-autoupdate";
        runtimeInputs = with pkgs; [ coreutils curl git ];
        text = builtins.readFile ./../scripts/autoupdate.sh;
      })
    ];

    launchd.agents.nix-config-autoupdate = lib.mkIf pkgs.stdenv.isDarwin {
      enable = true;
      config = {
        ProgramArguments = [ command ];
        EnvironmentVariables = env;
        # Runs at the next wake if the Mac was asleep at 10:00.
        StartCalendarInterval = [{ Hour = 10; Minute = 0; }];
        StandardOutPath = "${config.home.homeDirectory}/Library/Logs/nix-config-autoupdate.log";
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/nix-config-autoupdate.log";
      };
    };

    systemd.user.services.nix-config-autoupdate = lib.mkIf pkgs.stdenv.isLinux {
      Unit.Description = "Pull nix-config and switch home-manager";
      Service = {
        Type = "oneshot";
        ExecStart = command;
        Environment = lib.mapAttrsToList (k: v: "${k}=${v}") env;
      };
    };
    systemd.user.timers.nix-config-autoupdate = lib.mkIf pkgs.stdenv.isLinux {
      Unit.Description = "Daily nix-config pull-and-switch";
      Timer = {
        OnCalendar = "*-*-* 10:00:00";
        Persistent = true;
      };
      Install.WantedBy = [ "timers.target" ];
    };
  };
}
