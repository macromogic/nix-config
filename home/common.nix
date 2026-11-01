# Shared by every machine. Mirrors the old gist's _setup.sh.
{ config, pkgs, lib, inputs, ... }:

let
  # ZSH_CUSTOM for oh-my-zsh, holding plugins that are not in nixpkgs.
  omzCustom = pkgs.linkFarm "omz-custom" [
    { name = "plugins/bark"; path = inputs.bark; }
  ];

  agents = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
  # The llm-agents wrapper defaults CLAUDE_CODE_CERT_STORE to `system`, whose
  # store comes up empty on macOS (UNABLE_TO_GET_ISSUER_CERT_LOCALLY). Restore
  # Claude Code's own default in the binary itself, so it holds however claude
  # is started (T3 Code, herdr, launchd), not only from a fresh shell.
  claude-code = pkgs.symlinkJoin {
    name = "claude-code-${agents.claude-code.version}";
    paths = [ agents.claude-code ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/claude --set-default CLAUDE_CODE_CERT_STORE bundled,system
    '';
  };
  # OpenCode 2.x, which T3 Code wants (>= 2.0.18). llm-agents installs it as
  # `opencode2` to coexist with its 1.x package; we only carry 2.x, so give
  # it upstream's name back. 2.x converts the 1.x database in place.
  opencode = pkgs.runCommand "opencode-${agents.opencode2.version}" { } ''
    mkdir -p $out/bin
    ln -s ${agents.opencode2}/bin/opencode2 $out/bin/opencode
  '';
  # T3 Code with paired sessions lasting two years instead of 30 days. Sessions
  # never renew, so each client would otherwise be re-paired with every
  # server monthly; the servers are reachable on the tailnet only, and a lost
  # device is revoked with `t3 auth session revoke`. The constant sits in a
  # bundle whose name changes per release, so the build fails if it moves
  # rather than quietly going back to 30 days. dist is copied, not linked:
  # node resolves symlinked modules to their target and would load the
  # original bundle. Wrapped as llm-agents wraps it, with its own node.
  t3code =
    let
      unwrapped = agents.t3code.unwrapped;
      node = inputs.llm-agents.inputs.nixpkgs.legacyPackages.${pkgs.stdenv.hostPlatform.system}.nodejs_24;
    in
    pkgs.runCommand "t3code-${unwrapped.version}" { nativeBuildInputs = [ pkgs.makeBinaryWrapper ]; } ''
      src=${unwrapped}/libexec/t3code/apps/server
      dst=$out/libexec/t3code/apps/server
      mkdir -p $dst
      for f in $src/*; do
        [ "$(basename "$f")" = dist ] || ln -s "$f" $dst/
      done
      cp -r $src/dist $dst/dist
      chmod -R u+w $dst/dist
      old='const DEFAULT_SESSION_TTL = days(30);'
      bundle=$(grep -lF "$old" $dst/dist/*.mjs)
      [ "$(echo "$bundle" | wc -l)" -eq 1 ] || { echo "t3code: session TTL constant not found exactly once" >&2; exit 1; }
      substituteInPlace "$bundle" --replace-fail "$old" 'const DEFAULT_SESSION_TTL = days(730);'
      makeWrapper ${lib.getExe node} $out/bin/t3 \
        --add-flags $dst/dist/bin.mjs \
        --prefix PATH : ${lib.makeBinPath agents.t3code.providerPackages}
      ln -s ${unwrapped}/share $out/share
    '';
in
{
  home.stateVersion = "25.11";
  programs.home-manager.enable = true;

  home.packages = with pkgs; [
    # LazyVim and its dependencies
    neovim
    ripgrep
    fd
    lazygit
    gnumake
    clang-tools
    unzip
    nodejs_24

    gh
    cmake
    sourceHighlight # used by LESSOPEN
    tmux
    screen
    uv
    herdr

    (writeShellApplication {
      name = "git-setup";
      runtimeInputs = [ git ];
      text = builtins.readFile ./../scripts/git-setup.sh;
    })
    claude-code
    opencode
    t3code # `t3`: T3 Code server and CLI
    (writeShellApplication {
      name = "t3-pair";
      runtimeInputs = [ t3code jq ];
      text = builtins.readFile ./../scripts/t3-pair.sh;
    })
  ] ++ (with agents; [
    codex
  ]);

  # `, <cmd>` runs a command from nixpkgs without installing it. Also gives
  # zsh a command-not-found hint naming the package that provides <cmd>.
  programs.nix-index-database.comma.enable = true;

  # Resolve `nixpkgs#...` (comma, nix shell, nix run) to the pinned input
  # instead of re-downloading the latest unstable tarball.
  nix.registry.nixpkgs.flake = inputs.nixpkgs;

  home.sessionVariables = {
    LANG = "en_US.UTF-8";
    LC_ALL = "en_US.UTF-8";
    LESSOPEN = "| ${pkgs.sourceHighlight}/bin/src-hilite-lesspipe.sh %s";
    LESS = " -R ";
    # Versions come from the llm-agents input; a self-update cannot write
    # to the store. (claude-code's wrapper already disables its updater.)
    OPENCODE_DISABLE_AUTOUPDATE = "1";
    # T3 Code product events and T3 Connect relay tracing. Read by the server
    # and the desktop app (which picks it up from the login shell).
    T3CODE_TELEMETRY_ENABLED = "false";
  };

  home.file = {
    ".tmux.conf".source = ./../dotfiles/tmux.conf;
    ".screenrc".source = ./../dotfiles/screenrc;
  } // lib.genAttrs (import ./../agents/targets.nix) (_: {
    text = builtins.readFile ./../agents/AGENTS.md;
  });

  programs.zsh = {
    enable = true;
    # rustup/cargo, installed outside Nix.
    envExtra = ''
      [[ -f "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"
    '';
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    oh-my-zsh = {
      enable = true;
      plugins = [ "git" "z" "sudo" "tmux" "bark" ];
      custom = "${omzCustom}";
    };

    plugins = [{
      name = "powerlevel10k";
      src = pkgs.zsh-powerlevel10k;
      file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
    }];

    initContent = lib.mkMerge [
      # p10k instant prompt must run before anything that prints.
      (lib.mkBefore ''
        if [[ -r "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh" ]]; then
          source "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh"
        fi
      '')
      ''
        [[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh
        # Unmanaged on purpose: never commit secrets to this repo.
        [[ -f ~/.zshrc_secrets ]] && source ~/.zshrc_secrets
        export PATH="$HOME/.local/bin:$PATH"
        export PATH="$HOME/nora/bin:$PATH"
      ''
      # Per-machine settings kept out of this repo (CUDA, research
      # toolchains, conda, ...). Sourced last so they win on PATH.
      (lib.mkOrder 2000 ''
        # `if`, not `&&`: a missing file must not leave $? = 1 at the
        # first prompt.
        if [[ -f ~/.zshrc_host ]]; then source ~/.zshrc_host; fi
      '')
    ];
  };

  # Leftover installer copies in ~/.local/bin win over the Nix ones on PATH
  # (that dir must stay first for host toolchains), so point them out.
  home.activation.agentCliLeftovers = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    for f in "$HOME"/.local/bin/{claude,codex,opencode} "$HOME"/.opencode/bin/opencode \
             "$HOME"/.nvm/versions/node/*/bin/{claude,codex,opencode}; do
      if [ -e "$f" ]; then
        echo "agent CLIs: leftover installer copy may shadow the Nix one: $f"
      fi
    done
  '';
}
