#!/usr/bin/env bash

export HOME=home
mkdir -p $HOME

# fake session id
export TERM_PROGRAM=testterm TERM_SESSION_ID=testid

export HISTIGNORE="history*:set*:echo*:source*:load_in_subshell*"
set -o history
history -s "$@"

load_in_subshell()(
	# "purpoise" for purpose and "y" to track history
	source hag.bash "$PWD/.config/hag" "porpoise" "y"

	echo "" # newline

	history -s "$@"

	# shouldn't exist until we exit
	! [[ -e .config/hag/porpoise/${TERM_SESSION_ID}.hag_rehydrate.bash ]]
)

load_in_subshell && {
	# but now it should exist
	cat .config/hag/porpoise/${TERM_SESSION_ID}.hag_rehydrate.bash
	[[ -e .config/hag/porpoise/${TERM_SESSION_ID}.hag_rehydrate.bash ]] && cat .config/hag/porpoise/${TERM_SESSION_ID}.hag_rehydrate.bash
}

source hag.bash "$PWD/.config/hag"

echo "" # newline

history
