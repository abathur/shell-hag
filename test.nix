{ hag
, shellcheck
, bats
, bashInteractive
, socat
, sqlite
}:

rec {
  upstream = hag.unresholved.overrideAttrs (old: {
    name = "${hag.name}-tests";
    dontInstall = true; # just need the build directory
    installCheckInputs = [ hag shellcheck bats bashInteractive socat sqlite ];
    doInstallCheck = true;
    installCheckPhase = ''
      ${bats}/bin/bats tests
      touch $out
    '';
  });
}
