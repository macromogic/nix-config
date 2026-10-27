# Dev servers reached over SSH: where agent sessions actually run.
{ ... }:

{
  # Classic (filled) prompt, so a remote shell is obvious at a glance.
  home.file.".p10k.zsh".source = ./../../dotfiles/p10k-remote.zsh;

  programs.zsh.oh-my-zsh.plugins = [ "docker-compose" ];
}
