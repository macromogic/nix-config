# Git checkouts that stay mutable instead of living in the Nix store: you
# edit, commit and push them in place, and tools that write into them
# (LazyVim's lock file, `nora update`) keep working. Each is cloned on the
# first switch, fast-forwarded by the daily autoupdate when that is safe,
# and its skills are linked into every agent. scripts/clones.sh does the
# work; `nix-config-clones status` shows what would block a pull.
#
# Own repos only, so the 7-day rule for upstream inputs doesn't apply.
{ config, lib, pkgs, ... }:

let
  cfg = config.nixConfig.clones;
  enabled = lib.filterAttrs (_: c: c.enable) cfg;

  hook = name: text: pkgs.writeShellScript "clone-hook-${name}" text;

  manifest = pkgs.writeText "nix-config-clones" (lib.concatStrings (lib.mapAttrsToList
    (name: c: lib.concatStringsSep "\t" [
      name
      c.path
      c.url
      c.branch
      (if c.skillDirs == [ ] then "-" else lib.concatStringsSep ":" c.skillDirs)
      (if c.hook == null then "-" else "${hook name c.hook}")
    ] + "\n")
    enabled));

  tool = pkgs.writeShellApplication {
    name = "nix-config-clones";
    runtimeInputs = with pkgs; [ coreutils git ];
    text = builtins.readFile ./../scripts/clones.sh;
  };
in
{
  options.nixConfig.clones = lib.mkOption {
    description = "Mutable git checkouts kept up to date on this machine.";
    default = { };
    type = lib.types.attrsOf (lib.types.submodule {
      options = {
        enable = lib.mkEnableOption "this checkout" // { default = true; };
        path = lib.mkOption {
          type = lib.types.str;
          description = "Where it lives, relative to $HOME.";
        };
        url = lib.mkOption {
          type = lib.types.str;
          description = "Public HTTPS URL; timers have no SSH agent.";
        };
        branch = lib.mkOption {
          type = lib.types.str;
          default = "master";
        };
        skillDirs = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Dirs whose subfolders holding SKILL.md are linked into every agent.";
        };
        hook = lib.mkOption {
          type = lib.types.nullOr lib.types.lines;
          default = null;
          description = ''
            Shell run inside the checkout on every switch and after a pull
            that moved it, with OLD/NEW revisions (OLD empty after cloning).
          '';
        };
      };
    });
  };

  config = {
    nixConfig.clones = {
      # LazyVim config. Plugins follow the committed lazy-lock.json, which
      # only the lazyvim repo's weekly CI job updates; machines never run
      # `:Lazy update` themselves. On startup lazy installs missing plugins
      # and rewrites the lock from what is installed, before the restore
      # reads it; so restore again from the committed lock. A lock still
      # dirty after that means a plugin couldn't be checked out.
      nvim = {
        path = ".config/nvim";
        url = "https://github.com/macromogic/lazyvim.git";
        hook = ''
          git=${pkgs.git}/bin/git
          if [ -n "$OLD" ] && ! $git diff --quiet "$OLD" "$NEW" -- lazy-lock.json; then
            log=$HOME/.local/state/nix-config-nvim-restore.log
            ${pkgs.coreutils}/bin/mkdir -p "''${log%/*}"
            : >"$log"
            restore() {
              ${pkgs.coreutils}/bin/timeout 600 ${pkgs.neovim}/bin/nvim --headless "+Lazy! restore" +qa >>"$log" 2>&1
            }
            restore
            $git checkout -- lazy-lock.json
            restore
            if ! $git diff --quiet -- lazy-lock.json; then
              $git checkout -- lazy-lock.json
              echo "nvim: plugins don't match lazy-lock.json after restore; see $log" >&2
              exit 1
            fi
          fi
        '';
      };

      # Nora installs its own skills (with short aliases), and updates
      # itself with `nora update`. install-skills is idempotent; it fails
      # only when no agent is installed yet.
      nora = {
        path = "nora";
        url = "https://github.com/macromogic/nora.git";
        hook = ''
          ${pkgs.python3}/bin/python3 bin/nora install-skills \
            || echo "nora: no ~/.claude or ~/.codex yet; rerun 'nora install-skills' later"
        '';
      };

      # Transcription CLI; its skill calls the `ytcc` wrapper below.
      ytcc = {
        path = lib.mkDefault "ytcc";
        url = "https://github.com/macromogic/ytcc.git";
        skillDirs = [ ".agents/skills" ];
      };
    };

    home.packages = [ tool ]
      ++ lib.optionals (enabled ? ytcc) [
      pkgs.ffmpeg-headless
      # Runs ytcc from its checkout in any directory; uv syncs its venv.
      # The venv lives in the cache, not the checkout: iCloud flags files
      # under dot-folders in ~/Documents as hidden, and Python >= 3.13
      # skips hidden .pth files, which breaks the editable install.
      (pkgs.writeShellScriptBin "ytcc" ''
        export UV_PROJECT_ENVIRONMENT="''${XDG_CACHE_HOME:-$HOME/.cache}/ytcc/venv"
        exec ${pkgs.uv}/bin/uv run --quiet --project "$HOME/${cfg.ytcc.path}" ytcc "$@"
      '')
    ];

    xdg.configFile."nix-config/clones".source = manifest;

    # Never fails the switch: problems are reported, not fatal.
    home.activation.clones = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run env NIX_CONFIG_CLONES=${manifest} PATH="${pkgs.openssh}/bin:$PATH" \
        ${lib.getExe tool} sync || echo "clones: sync failed"
    '';
  };
}
