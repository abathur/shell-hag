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
    shellswain.url = "github:abathur/shellswain/v0.1.0";
    bats-require = {
      url = "github:abathur/bats-require";
      follows = "shellswain/bats-require";
    };
  };

  outputs = { self, nixpkgs, flake-utils, flake-compat, shellswain, bats-require }:
  let
    sharedInit = pkgs: ''
      source ${pkgs.hag}/bin/hag.bash
    '';
    sharedOptions = userHome: pkgs: with nixpkgs.lib; {
      enable = mkEnableOption "hag";
      # enable = mkOption {
      #   description = "Whether to enable hag.";
      #   default = false;
      #   type = types.bool;
      # };

      init = mkOption {
        default = true;
        type = types.bool;
        description = ''
          Whether to auto-add interactiveShellInit for hag.

          Disable this if you need to control where and how
          hag is sourced.
        '';
      };

      package = mkPackageOption pkgs "hag" { };

      # package = mkOption {
      #   description = "Hag package to use.";
      #   default = pkgs.hag;
      #   defaultText = "pkgs.hag";
      #   type = types.package;
      # };

      user = mkOption {
        type = types.str;
        default = "root";
        description = ''
          User to aggregate history for.
        '';
      };

      # TODO: see if other modules do anything obvious about XDG?
      dataDir = mkOption {
        type = types.str;
        default = "${userHome}/.config/hag";
        description = ''
          Data directory for hag.
        '';
      };

      # TODO: this is only wired up for darwin atm, but I'm mainly using
      #       it as a debug affordance anyways--so perhaps I should
      #       weigh whether it should exist or be unset by default?
      logFile = mkOption {
        type = types.str;
        default = "${userHome}/hag.log";
        description = ''
          Logfile for hag.
        '';
      };
    };
    testUser = "user1";
    testPassword = "password1234";
  in
    {
      overlays.default = nixpkgs.lib.composeExtensions shellswain.overlays.default (final: prev: {
        hag = final.callPackage ./hag.nix { };
      });
      darwinModules.hag = { config, pkgs, lib, ... }:
      let
        cfg = config.programs.hag;
        userHome = config.users.users.${cfg.user}.home;
      in {
        options.programs.hag = (sharedOptions userHome pkgs);
        # TODO: either update to track nixos, or factor common parts back out again?
        config = lib.mkIf cfg.enable {
          launchd.user.agents.hag = {
            command = "${cfg.package}/bin/hagd.bash '${cfg.package}' '${cfg.dataDir}'";
            serviceConfig = {
              StandardOutPath = builtins.toPath "${cfg.logFile}";
              StandardErrorPath = builtins.toPath "${cfg.logFile}";
              RunAtLoad = true;
              KeepAlive = true;
            };
          };
          # TODO: unlike the nixos version, this is untested until you try it in nix darwin
          programs.bash.interactiveShellInit = lib.optionalString cfg.init (sharedInit pkgs);
        };
      };
      # darwinModules.default = self.darwinModules.${system}.hag;

      nixosModules.hag = { config, pkgs, lib, ... }:
      let
        cfg = config.programs.hag;
        userHome = config.users.users.${cfg.user}.home;
      in {
        options.programs.hag = (sharedOptions userHome pkgs);
        config = lib.mkIf cfg.enable {
          systemd.services.hag = {
            description = "Shell-hag";
            # TODO: IDK about wantedBy and after
            wantedBy = [ "multi-user.target" ];
            after = [ "network.target" ];
            serviceConfig = {
              ExecStart = "${cfg.package}/bin/hagd.bash '${cfg.package}' '${cfg.dataDir}'";
              Restart = "on-failure";
              User = "${cfg.user}";
            };
          };
          programs.bash.interactiveShellInit = lib.optionalString cfg.init (sharedInit pkgs);
        };
      };
      # nixosModules.default = self.darwinModules.${system}.hag;
      # shell = ./shell.nix;
      checks.x86_64-linux.integration = let
        system = "x86_64-linux";
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ self.overlays.default ];
        };
      in pkgs.nixosTest {
        name = "hag-integration";

        nodes.system1 = { config, pkgs, ... }: {
          imports = [
            self.nixosModules.hag
          ];

          programs.hag = {
            user = "${testUser}";
            enable = true;
          };
          # programs.zsh.interactiveShellInit = ''
          #   source ${pkgs.hag}/bin/hag.bash
          # '';

          users = {
            mutableUsers = false;

            users = {
              "${testUser}" = {
                isNormalUser = true;
                password = "${testPassword}";
              };
            };
          };
          environment.systemPackages = [
            # TODO: could probably de-dupe this with hag's real
            #       test suite...
            (pkgs.writeScriptBin "expect-bash" ''
              #!${pkgs.expect}/bin/expect -df

              spawn env TERM=xterm ${pkgs.bashInteractive}/bin/bash -i

              expect "hag doesn't have a purpose; please set one:" {
                send "porpoise\n"
                expect "Should hag track the history for purpose 'porpoise'" {
                  send -- "y\r"
                  expect "hag is tracking history" {
                    send -- "uname -a\r"
                    expect "NixOS" {
                      send "echo bash displayed hag > rage\r"
                      send -- "exit\r"
                    }
                  }
                }
              } timeout {
                send_user "\nbash failed to display hag\n"
                exit 1
              }

              expect eof
            '')
          ];
        };

        testScript = ''
          system1.wait_for_unit("multi-user.target")
          system1.wait_until_succeeds("pgrep -f 'agetty.*tty1'")

          with subtest("open virtual console"):
              # system1.fail("pgrep -f 'agetty.*tty2'")
              system1.send_key("alt-f2")
              system1.wait_until_succeeds("[ $(fgconsole) = 2 ]")
              system1.wait_for_unit("getty@tty2.service")
              system1.wait_until_succeeds("pgrep -f 'agetty.*tty2'")

          with subtest("Log in as ${testUser} on new virtual console"):
              system1.wait_until_tty_matches("2", "login: ")
              system1.send_chars("${testUser}\n")
              system1.wait_until_tty_matches("2", "login: ${testUser}")
              system1.wait_until_succeeds("pgrep login")
              system1.wait_until_tty_matches("2", "Password: ")
              system1.send_chars("${testPassword}\n")
              system1.wait_until_tty_matches("2", "$")

          assert "bash displayed hag" in system1.succeed("su -l ${testUser} -c 'expect-bash'")

          assert "uname" in system1.succeed("cat /home/${testUser}/.config/hag/porpoise/.bash")

          assert "ingesting" in system1.succeed("journalctl -u hag.service")
        '';
      };
    } // flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [
            bats-require.overlays.default
            shellswain.overlays.default
            self.overlays.default
          ];
        };
      in
        {
          packages = {
            inherit (pkgs) hag;
            default = pkgs.hag;
          };
        }
    );
}
