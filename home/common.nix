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
  ] ++ (with agents; [
    codex
    t3code # `t3`: T3 Code server and CLI
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
