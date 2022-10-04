{ pkgs ? import <nixpkgs> { }, ... }:

with pkgs;
pkgs.callPackage ./test.nix { }
