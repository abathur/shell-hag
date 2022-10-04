#!/usr/bin/env bash

# TODO: fold expand_aliases down into the API if it's essential?
shopt -s expand_aliases

export HOME=.
# mkdir -p $HOME

# fake session id
export TERM_PROGRAM=testterm TERM_SESSION_ID=testid

# database shouldn't exist before starting daemon
if [[ -e .config/hag/.db.sqlite3 ]]; then
	exit 1
fi

hagd.bash "" ".config/hag" &

# database should exist once the daemon's going
until [[ -e .config/hag/.db.sqlite3 ]]; do
	:
done

function load_in_subshell()(
	# "purpose" via stdin
	source hag.bash ".config/hag" <<< porpoise

	echo "" # newline

	history

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
)

set -e
load_in_subshell "uname" && [[ "$(sqlite3 .config/hag/.db.sqlite3 "select count(*) from log")" == "1" ]]

load_in_subshell "uname" && [[ "$(sqlite3 .config/hag/.db.sqlite3 "select count(*) from log")" == "2" ]]
set +e

(
	source hag.bash ".config/hag" <<< porpoise
	echo "" # newline
	echo "before clear:"
	history
	history -c
	echo "after clear:"
	history

	hag regenerate

	echo "after regenerate:"
	history
)
