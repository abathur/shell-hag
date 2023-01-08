#with import <nixpkgs> {};
{ lib
, resholve
, fetchFromGitHub
, bashInteractive
, coreutils
, findutils
, gnugrep
, gnused
, shellswain
, smenu
, sqlite
, rlwrap
# history daemon
, python3
, libossp_uuid
, callPackage
}:
let


  # service/daemon

in
resholve.mkDerivation rec {
  pname = "hag";
  version = "unreleased";

  # src = fetchFromGitHub {
  #   owner = "abathur";
  #   repo = "shell-hag";
  #   # rev = "v${version}";
  #   rev = "acb6beff57438a84d0d63e7f8fddb3bed72834c6";
  #   hash = "sha256-eynd6be/xzg2g5kSjSOvXmIj5Nbgv8eFzlOe7EI3GQc=";
  # };
  src = lib.cleanSource ./.;
  buildInputs = [ bashInteractive python3 ];

  solutions = {
    profile = {
      scripts = [ "bin/hag.bash" ];
      interpreter = "none";
      keep = {
        source = [ "$HAG_PURPOSE_PWD_FILE" ];
        command = [ "$command_path" ];
        rlwrap = [ "$command_path" ];
        "$command_history_file" = true;
      };

      inputs = [
        coreutils
        findutils
        gnugrep
        shellswain
        sqlite
        rlwrap
      ];
    };
    cmd = {
      scripts = [ "bin/hag_import_history.bash" ];
      interpreter = "${bashInteractive}/bin/bash";

      inputs = [
        coreutils
        gnused
        smenu
      ];
    };
    daemon = {
      scripts = [ "bin/hagd.bash" ];
      # doesn't require interactive, but we already use it...
      interpreter = "${bashInteractive}/bin/bash";
      inputs = [
        libossp_uuid
        coreutils
        sqlite
        python3
        "libexec/daemon.py"
      ];
      fix = {
        "$HAG_SRC" = [ "${placeholder "out"}" ];
      };
    };
  };

  prePatch = ''
    patchShebangs daemon.py tests
  '';

  makeFlags = [ "prefix=${placeholder "out"}" ];

  doCheck = false;

  # TODO: below likely needs fixing
  passthru.tests = callPackage ./test.nix { };

  meta = with lib; {
    description = "A shell history aggregator";
    homepage = https://github.com/abathur/shell-hag;
    license = licenses.mit;
    maintainers = with maintainers; [ abathur ];
    platforms = platforms.all;
  };
}
