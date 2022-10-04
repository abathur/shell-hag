#with import <nixpkgs> {};
{ lib
, resholve
, fetchFromGitHub
, bashInteractive_5
, coreutils
, findutils
, gnugrep
, gnused
, shellswain
, smenu
, sqlite
, rlwrap
, doCheck ? false
, shellcheck
}:
let


  # service/daemon

in
resholve.mkDerivation rec {
  pname = "hag";
  version = "unreleased";

  src = fetchFromGitHub {
    owner = "abathur";
    repo = "shell-hag";
    # rev = "v${version}";
    rev = "acb6beff57438a84d0d63e7f8fddb3bed72834c6";
    hash = "sha256-eynd6be/xzg2g5kSjSOvXmIj5Nbgv8eFzlOe7EI3GQc=";
  };
  # src = lib.cleanSource ../../../../work/hag;

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
      interpreter = "${bashInteractive_5}/bin/bash";

      inputs = [
        coreutils
        gnused
        smenu
      ];
    };
  };

  makeFlags = [ "prefix=${placeholder "out"}" ];

  inherit doCheck;
  # checkInputs = [ shellcheck ];

  meta = with lib; {
    description = "A shell history aggregator";
    homepage = https://github.com/abathur/shell-hag;
    license = licenses.mit;
    maintainers = with maintainers; [ abathur ];
    platforms = platforms.all;
  };
}
