{ hag
, shellcheck
, bats
, bats-require
, bashInteractive
, expect
, sqlite
}:

{
  upstream = hag.unresholved.overrideAttrs (old: {
    name = "${hag.name}-tests";
    dontInstall = true; # just need the build directory
    prePatch = ''
      patchShebangs .
    '';
    installCheckInputs = [
      hag
      shellcheck
      (bats.withLibraries (p: [ bats-require ]))
      bashInteractive
      expect
      sqlite
    ];
    doInstallCheck = true;
    installCheckPhase = ''
      make check
      touch $out
    '';
  });
}
