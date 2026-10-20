{
  description = "macmo's home environments";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Prebuilt package index for comma, refreshed weekly upstream.
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Agent CLIs (claude-code, codex, opencode), updated daily upstream.
    # Deliberately not following our nixpkgs, so builds match
    # cache.numtide.com.
    llm-agents.url = "github:numtide/llm-agents.nix";
    # Custom oh-my-zsh plugin, not a flake.
    bark = {
      url = "github:macromogic/bark";
      flake = false;
    };
  };

  outputs = { nixpkgs, home-manager, nix-index-database, ... }@inputs:
    let
      # role is what a machine is for (local | remote); the platform module
      # follows from system, so hosts never pick it by hand.
      mkHome = { system, username, role, modules ? [ ] }:
        let
          isDarwin = nixpkgs.lib.hasSuffix "darwin" system;
        in
        home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.${system};
          extraSpecialArgs = { inherit inputs; };
          modules = [
            nix-index-database.homeModules.nix-index
            ./home/common.nix
            ./home/roles/${role}.nix
            (if isDarwin then ./home/platforms/darwin.nix else ./home/platforms/linux.nix)
            {
              home.username = username;
              home.homeDirectory = (if isDarwin then "/Users/" else "/home/") + username;
            }
          ] ++ modules;
        };
    in
    {
      # Activate with: nix run home-manager -- switch --flake .#<name>
      homeConfigurations = {
        "macmo@local" = mkHome {
          system = "aarch64-darwin";
          username = "macmo";
          role = "local";
        };

        "wh25@tdx" = mkHome {
          system = "x86_64-linux";
          username = "wh25";
          role = "remote";
        };

        # Template for dev servers: copy, rename, adjust system/username.
        "macmo@remote-template" = mkHome {
          system = "x86_64-linux";
          username = "macmo";
          role = "remote";
        };
      };
    };
}
