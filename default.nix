#with import <nixpkgs> {};
{ stdenv, lib, resholvePackage, fetchFromGitHub, bashInteractive_5, coreutils, findutils, gnugrep, gnused, shellswain, smenu, sqlite, rlwrap
, doCheck ? false, shellcheck }:
let


  # service/daemon

in
resholvePackage rec {
  pname = "hag";
  version = "unreleased";

  src = fetchFromGitHub {
    owner = "abathur";
    repo = "shell-hag";
    # rev = "v${version}";
    rev = "130db6753f0a410ffa4111836de720bd295e0b9b";
    hash = "sha256-w5dHJOOyCTor9xj77EsTzMZrU5QWTB8Iw4kUiKibn7w=";
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
