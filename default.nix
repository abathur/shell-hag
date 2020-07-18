#with import <nixpkgs> {};
{ stdenv, lib, resholved, fetchFromGitHub, bashInteractive_5, coreutils, findutils, gnugrep, gnused, shellswain, smenu, sqlite, rlwrap
, doCheck ? true, shellcheck }:
let


  # service/daemon

in
resholved.buildResholvedPackage rec {
  pname = "hag";
  version = "unreleased";

  src = fetchFromGitHub {
    owner = "abathur";
    repo = "shell-hag";
    # rev = "v${version}";
    rev = "3c635774abc3f55f916d756619c6a2b846a7cc2b";
    sha256 = "10mngwq0malh2rqyh0brgh8crn3ahlmpxhi609y70mlzqrldam8n";
  };
  # src = lib.cleanSource ../../../../work/hag;

  scripts = [ "hag.bash" "hag_import_history.bash" ];
  allow = {
    source = [ "HAG_PURPOSE_PWD_FILE" ];
    command = [ "command_path" ];
  };


  inputs = [
    coreutils
    findutils
    gnugrep
    gnused
    shellswain
    smenu
    sqlite
    rlwrap
  ];

  makeFlags = [ "prefix=${placeholder "out"}" ];

  inherit doCheck;
  checkInputs = [ shellcheck ];

  meta = with stdenv.lib; {
    description = "A shell history aggregator";
    homepage = https://github.com/abathur/shell-hag;
    license = licenses.mit;
    maintainers = with maintainers; [ abathur ];
    platforms = platforms.all;
  };


}
