cat <<EOF
{
  description = "SIGH";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs";
    darwin = {
      url = "github:lnl7/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hag.url = "github:abathur/shell-hag/$GITHUB_SHA";
  };

  outputs = { self, nixpkgs, hag, ... }@inputs: {
    darwinConfigurations.ci = let
      system = "x86_64-darwin";
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ hag.overlays.default ];
      };
    in inputs.darwin.lib.darwinSystem rec {
      system = "x86_64-darwin";
      inherit inputs;
      specialArgs = {
        inherit pkgs;
      };
      modules = [
        hag.darwinModules.hag
        (
          { config, pkgs, hag, ... }:

          {
            programs.bash.enable = true;
            programs.hag = {
              user = "$USER";
              enable = true;
            };

            users.users."$USER".home = "/Users/runner";

            system.stateVersion = 4;
            nix.useDaemon = true;
          }
        )
      ];
    };
  };
}
EOF
