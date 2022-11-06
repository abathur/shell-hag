#!/usr/bin/env bash

(
	fern(){
		echo hehe
	}

	export HOME=home
	mkdir -p $HOME

	# fake session id
	export TERM_PROGRAM=testterm TERM_SESSION_ID=testid

	# "purpoise" for purpose and "y" to track history
	source hag.bash "$PWD/.config/hag" "porpoise" "y"

	echo "" # newline

	function hag.passable.wrap_command(){
		# shellcheck disable=SC2155
		local wrap_command=1
		local -p # echo these vars for export
	}

	function hag.aggregator.haggregate(){
		hag.hook "$1" pre_cmd none post_cmd

		hag.pass "$1" "pre" pre_command_timing
		hag.pass "$1" "all" command_path history_files wrap_command
		hag.pass "$1" "post" post_command_timing
	}

	hag.track "$1" hag.aggregator.haggregate

	# TODO: not a fan of how shellswain's testing woes also leak
	# in here...; at least wrap this up in helpers?
	eval "
	_test(){
		history -s $@
		eval \"\${PS0@P}\"
		$@
		eval \"\${PROMPT_COMMAND[1]}\"
		echo \"\${PS1@P}\"
	}
	"

	# simulate first prompt
	eval "${PROMPT_COMMAND[1]}"
	echo "${PS1@P}"

	_test

	# shouldn't exist until we exit
	! [[ -e .config/hag/porpoise/testid.hag_dehydrate.bash ]]
) && {
	# but now it should exist
	[[ -e .config/hag/porpoise/testid.hag_dehydrate.bash ]] && cat .config/hag/porpoise/testid.hag_dehydrate.bash
}
