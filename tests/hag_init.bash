#!/usr/bin/env bash

# TODO: fold expand_aliases down into the API if it's essential?
shopt -s expand_aliases

export HOME=home
mkdir -p $HOME

# fake session id
export TERM_PROGRAM=testterm TERM_SESSION_ID=testid

(
	[[ -z "$HAG_PURPOSE" ]] && echo "no initial purpose"

	# "purpose" via stdin
	source hag.bash "$PWD/.config/hag" <<< porpoise

	echo "" # newline

	[[ -e .config/hag/porpoise/.init ]] && echo ".init file created"
)

(
	# "purpose" via .init file now
	source hag.bash "$PWD/.config/hag"

	echo ""

	# shouldn't exist until we exit
	[[ "$HAG_PURPOSE" == "porpoise" ]] && echo "purpose restored from .init"
)
