# Shared by every machine. Mirrors the old gist's _setup.sh.
{ config, pkgs, lib, inputs, ... }:

let
  # ZSH_CUSTOM for oh-my-zsh, holding plugins that are not in nixpkgs.
  omzCustom = pkgs.linkFarm "omz-custom" [
    { name = "plugins/bark"; path = inputs.bark; }
  ];
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
  ] ++ (with inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}; [
    claude-code
    codex
    opencode
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
    # The llm-agents wrapper defaults this to `system`, whose store comes up
    # empty on macOS (UNABLE_TO_GET_ISSUER_CERT_LOCALLY). Restore Claude
    # Code's own default.
    CLAUDE_CODE_CERT_STORE = "bundled,system";
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

  # LazyVim writes lazy-lock.json into its config dir, so it stays a
  # mutable git checkout rather than a read-only store path.
  home.activation.lazyvim = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -d "$HOME/.config/nvim" ]; then
      run ${pkgs.git}/bin/git clone https://github.com/macromogic/lazyvim.git "$HOME/.config/nvim"
    fi
  '';

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

  # Nora updates itself with `nora update` (git pull), so it is also a
  # mutable checkout. install-skills is idempotent; it fails only when no
  # agent is installed yet, which must not abort activation.
  home.activation.nora = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -d "$HOME/nora" ]; then
      run ${pkgs.git}/bin/git clone https://github.com/macromogic/nora.git "$HOME/nora"
    fi
    run ${pkgs.python3}/bin/python3 "$HOME/nora/bin/nora" install-skills \
      || echo "nora: no ~/.claude or ~/.codex yet; rerun 'nora install-skills' later"
  '';
}
