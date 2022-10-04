#!/usr/bin/env bash

# TODO: fold expand_aliases down into the API if it's essential?
shopt -s expand_aliases

source hag.bash ".config/hag" <<< porpoise

echo "" # newline

[[ -d "$HAG_SESSION_DIR" ]] && echo "$HAG_SESSION_DIR"
