# macOS-only bits, carried over from the existing ~/.zshrc.
# Homebrew still owns casks and anything not yet migrated.
{ lib, ... }:

{
  home.sessionVariables = {
    IMAGEIO_FREEIMAGE_LIB = "/opt/homebrew/opt/freeimage/lib/libfreeimage.dylib";
    NVM_DIR = "$HOME/.nvm";
  };

  # AeroSpace itself comes from Homebrew; only its config lives here.
  xdg.configFile."aerospace/aerospace.toml".source = ./../../dotfiles/aerospace.toml;

  # Login shells that never read .zshrc still need Homebrew.
  programs.zsh.profileExtra = ''
    eval "$(/opt/homebrew/bin/brew shellenv)"
  '';

  programs.zsh.initContent = lib.mkAfter ''
    eval "$(/opt/homebrew/bin/brew shellenv)"
    export PATH="/opt/homebrew/opt/bzip2/bin:$PATH"

    export PATH="$HOME/.jenv/bin:$PATH"
    eval "$(jenv init -)"

    __conda_setup="$('/opt/homebrew/anaconda3/bin/conda' 'shell.zsh' 'hook' 2> /dev/null)"
    if [ $? -eq 0 ]; then
      eval "$__conda_setup"
    elif [ -f "/opt/homebrew/anaconda3/etc/profile.d/conda.sh" ]; then
      . "/opt/homebrew/anaconda3/etc/profile.d/conda.sh"
    else
      export PATH="/opt/homebrew/anaconda3/bin:$PATH"
    fi
    unset __conda_setup

    [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
    [ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"

    # brew shellenv prepends /opt/homebrew/bin; put Nix back in front so
    # tools managed here win over leftover brew duplicates.
    export PATH="$HOME/.nix-profile/bin:$PATH"
  '';
}
