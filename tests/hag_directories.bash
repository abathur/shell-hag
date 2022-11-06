#!/usr/bin/env bash

# "purpoise" for purpose and "y" to track history
source hag.bash "$PWD/.config/hag" "porpoise" "y"

echo "" # newline

[[ -d "$HAG_SESSION_DIR" ]] && echo "$HAG_SESSION_DIR"
