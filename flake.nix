{
  inputs = {
    nixpkgs = {
      url = "github:nixos/nixpkgs/nixpkgs-unstable";
      follows = "shellswain/nixpkgs";
    };
    flake-utils = {
      url = "github:numtide/flake-utils";
      follows = "shellswain/flake-utils";
    };
    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
      follows = "shellswain/flake-compat";
    };
    shellswain.url = "github:abathur/shellswain/flaky-breaky-heart";
    bats-require = {
      url = "github:abathur/bats-require";
      follows = "shellswain/bats-require";
    };
  };

  outputs = { self, nixpkgs, flake-utils, flake-compat, shellswain, bats-require }:
    flake-utils.lib.eachDefaultSystem (system:
      with nixpkgs.lib;
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [
            (final: prev: {
              shellswain = shellswain.packages."${system}".default;
              bats-require = bats-require.packages."${system}".default;
            })
          ];
        };
        sharedOptions = {
          enable = mkOption {
            description = "Whether to enable hag.";
            default = false;
            type = types.bool;
          };

          package = mkOption {
            description = "Hag package to use.";
            default = pkgs.hag;
            defaultText = "pkgs.hag";
            type = types.package;
          };

          # TODO: XDG
          dataDir = mkOption {
            type = types.str;
            default = "${userHome}/.config/hag";
            description = ''
              Data directory for hag.
            '';
          };

          logFile = mkOption {
            type = types.str;
            default = "${userHome}/hag.log";
            description = ''
              Logfile for hag.
            '';
          };
        };
      in rec {
        packages.hag = pkgs.callPackage ./hag.nix { };
        packages.default = self.packages.${system}.hag;
        checks = pkgs.callPackages ./test.nix {
          inherit (packages) hag;
        };
        # checks = {
        #   hag = self.packages.${system}.hag;
        #   # tests = self.packages.${system}.hag.tests;
        # };
        # devShells.default = pkgs.callPackage ./shell.nix { };

        darwinModules.default = { config, pkgs, ... }:
        let cfg = config.programs.hag;
        in {
          options.programs.hag = sharedOptions;
          config = {
            launchd.user.agents.hag = {
              command = "${cfg.package}/bin/hagd.bash '${cfg.package}' '${cfg.dataDir}'";
              serviceConfig = {
                StandardOutPath = builtins.toPath "${cfg.logFile}";
                StandardErrorPath = builtins.toPath "${cfg.logFile}";
                RunAtLoad = true;
                KeepAlive = true;
              };
            };
            # TODO: probably don't need below now that this is resholved, but let's confirm before deleting it
            # environment.systemPackages = [ cfg.package ];
          };
        };
      }
    );
}
