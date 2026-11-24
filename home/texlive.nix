# Full TeX Live (several GB) on the machines that compile papers. It
# includes every package, so it also covers myanim's MathTex, and
# clones.nix leaves out its smaller TeX Live when this is on.
{ config, lib, pkgs, ... }:

{
  options.nixConfig.texliveFull = lib.mkEnableOption "the full TeX Live";

  config = lib.mkIf config.nixConfig.texliveFull {
    home.packages = [ pkgs.texliveFull ];
  };
}
