#!/usr/bin/env bash

# TODO: fold expand_aliases down into the API if it's essential?
function load_in_subshell()(
	shopt -s expand_aliases

	fern(){
		echo hehe
	}

	export HOME=home
	mkdir -p $HOME

	# fake session id
	export TERM_PROGRAM=testterm TERM_SESSION_ID=testid

	# "purpose" via stdin
	source hag.bash ".config/hag" <<< porpoise

	echo "" # newline

	history

	function hag.passable.wrap_command(){
		# shellcheck disable=SC2155
		local wrap_command=1
		local -p # echo these vars for export
	}

	function __haggregate(){
		hag.add_command_hooks "$1" hag.hook.pre_cmd none hag.hook.post_cmd

		hag.pass_per_command "$1" command_path history_files wrap_command
		hag.pass_pre_invocation "$1" pre_command_timing
		hag.pass_post_invocation "$1" post_command_timing
	}

	hag.track "$1" __haggregate

	# TODO: not a fan of how shellswain's testing woes also leak
	# in here...; at least wrap this up in helpers?
	eval "
	_test(){
		history -s $@
		eval \"\${PS0@P}\"
		$@
		eval \"\$PROMPT_COMMAND\"
		echo \"\${PS1@P}\"
	}
	"

	# simulate first prompt
	eval "${PS0@P}"
	eval "$PROMPT_COMMAND"
	echo "${PS1@P}"

	_test

	# shouldn't exist until we exit
	! [[ -e .config/hag/porpoise/testid.hag_dehydrate.bash ]]
)

load_in_subshell "$@" && {
	# but now it should exist
	[[ -e .config/hag/porpoise/testid.hag_dehydrate.bash ]] && cat .config/hag/porpoise/testid.hag_dehydrate.bash
}

load_in_subshell "$@"
