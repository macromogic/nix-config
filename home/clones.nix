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
  inherit (pkgs.stdenv.hostPlatform) isLinux;

  # Build environment for pycairo and manimpango: PKG_CONFIG_PATH and
  # CPATH for cairo and pango and everything they require, as the setup
  # hooks collect it inside a Nix build (pkg-config alone leaves out the
  # headers of private requirements such as xcb, which cairo's headers
  # include). Sourced by the myanim wrapper.
  myanimBuildEnv = pkgs.runCommand "myanim-build-env"
    {
      nativeBuildInputs = [ pkgs.pkg-config ];
      buildInputs = with pkgs; [ cairo pango ];
    } ''
    pkg-config --exists pangocairo cairo
    for v in ''${!PKG_CONFIG_PATH*}; do p+=''${p:+:}''${!v}; done
    IFS=:
    for d in $p; do
      d=''${d%/*/pkgconfig}/include
      if [ -d "$d" ]; then inc+=''${inc:+:}$d; fi
    done
    {
      echo "PKG_CONFIG_PATH=$p\''${PKG_CONFIG_PATH:+:\$PKG_CONFIG_PATH}"
      echo "CPATH=$inc\''${CPATH:+:\$CPATH}"
      echo "export PKG_CONFIG_PATH CPATH"
    } >$out
  '';

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

      # Manim educational-video skill and CLI. Its SKILL.md sits at the
      # repo root and refers to files beside it, so the whole checkout is
      # linked as the skill below, not via skillDirs.
      myanim = {
        path = lib.mkDefault "myanim";
        url = "https://github.com/macromogic/myanim.git";
        branch = "main";
      };
    };

    home.packages = [ tool ]
      ++ lib.optionals (enabled ? ytcc) [
      pkgs.ffmpeg-headless
      # Runs ytcc from its checkout in any directory; uv syncs its venv.
      # The venv lives in the cache, not the checkout: a checkout under an
      # iCloud-synced folder (~/Documents) gets its dot-folders flagged
      # hidden, and Python >= 3.13 skips hidden .pth files, which breaks
      # the editable install.
      (pkgs.writeShellScriptBin "ytcc" ''
        export UV_PROJECT_ENVIRONMENT="''${XDG_CACHE_HOME:-$HOME/.cache}/ytcc/venv"
        exec ${pkgs.uv}/bin/uv run --quiet --project "$HOME/${cfg.ytcc.path}" ytcc "$@"
      '')
    ]
      ++ lib.optionals (enabled ? myanim) [
      pkgs.ffmpeg-headless
      # Runs myanim from its checkout (venv in the checkout's .venv). pycairo
      # (and manimpango on Linux) has no wheel, so uv builds it: give it
      # cairo, pango, pkg-config and ninja from Nix rather than Homebrew or
      # apt. On Linux the Python and compiler come from Nix too: uv's own
      # Python uses the system glibc, older than the one Nix's cairo needs.
      (pkgs.writeShellScriptBin "myanim" (''
        export PATH="${lib.makeBinPath ([ pkgs.pkg-config pkgs.ninja ]
          ++ lib.optional isLinux pkgs.stdenv.cc)}:$PATH"
        . ${myanimBuildEnv}
      '' + lib.optionalString isLinux ''
        export UV_PYTHON=${pkgs.python312}/bin/python3.12 UV_PYTHON_DOWNLOADS=never
        # manylinux wheels (numpy) expect libstdc++ and zlib from the system.
        export LD_LIBRARY_PATH="${lib.makeLibraryPath [ pkgs.stdenv.cc.cc.lib pkgs.zlib ]}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
      '' + ''
        exec ${pkgs.uv}/bin/uv run --quiet --project "$HOME/${cfg.myanim.path}" myanim "$@"
      ''))
    ]
      # MathTex on Linux; the Mac uses MacTeX. Manim's template needs
      # standalone and preview, components/style.py libertinus-type1, which
      # loads fontaxes without declaring it.
      ++ lib.optional ((enabled ? myanim) && isLinux) (pkgs.texliveSmall.withPackages
      (ps: with ps; [ standalone preview libertinus-type1 fontaxes dvisvgm ]));

    xdg.configFile."nix-config/clones".source = manifest;

    home.file = lib.optionalAttrs (enabled ? myanim) (lib.genAttrs
      [ ".claude/skills/myanim" ".codex/skills/myanim" ]
      (_: {
        source = config.lib.file.mkOutOfStoreSymlink
          "${config.home.homeDirectory}/${cfg.myanim.path}";
      }));

    # Never fails the switch: problems are reported, not fatal.
    home.activation.clones = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run env NIX_CONFIG_CLONES=${manifest} PATH="${pkgs.openssh}/bin:$PATH" \
        ${lib.getExe tool} sync || echo "clones: sync failed"
    '';
  };
}
