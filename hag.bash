# shellcheck shell=bash

# Naming patterns:
# - hag-specific functions and events start with "hag"
# - namespace separators: '.' for functions and ':' for events
# - use function _names for likely-internal behavior

if [[ -z "$SHELLSWAIN_ABOARD" ]]; then
	# TODO: doc what this provides?
	# shellcheck disable=SC1090
	source shellswain.bash
fi

# local copy of this shellswain API function
function hag.track(){
	__shellswain_track "$@"
}

shopt -s histappend

# TODO: this is one of those things that I'd like a sort of compile-in utility kit for. Maybe resholve, or a more granular tool like it, can do this.
# TODO: also note that this still has big problems with losing window/tab titles.
function _set_terminal_title()
{
	# echo -n -e "\033]0;" "$@" "\007"
	printf '\e]1;%s\a' "$*"
}

# when interactive, $0 should be the shell; if it contains a slash AFAIK it'll be a script
if [[ $0 =~ / ]]; then
	# do something different if this is a script
	# (mainly a testing affordance)
	HAG_SHELL="$(basename "$0")"
else
	# capture the starting shell, sans leading -|.|/ if present
	HAG_SHELL="${0/-/}"
fi
# TODO: document why this is $1? Why isn't it considering a pre-set value and XDG? I guess it's just a more explicit API vision?
# TODO: maybe rename all of HAG_DIR to HAG_DATA_DIR?
HAG_DIR=${1:-~/.config/hag}
export HAG_DB="$HAG_DIR/.db.sqlite3"
__HAG_PREV_CMD_NUM=$HISTCMD
export HAG_PIPE="$HAG_DIR/.pipe"
export HAG_SESSION_DIR="$HAG_DIR/.sessions"

# If an outer shell passes HAG_SESSION_ID down to us accept it as-is, and do
# *NOT* attempt to compute other values usually derived from it.
# CAUTION: I am using HAG_SESSION_ID as shorthand for multiple variables that
# all need to be explicitly passed for this not to blow up in your face:
# HAG_SESSION_ID, HAG_SESSION_FILE, HAG_PURPOSE, HISTFILE
if [[ -n "$HAG_SESSION_ID" ]]; then
	hag._load_shell_history
else
	# Just Apple Terminal for now. Add new terminals later? Could also make user manually add? Maybe an install step?
	HAG_SESSION_ID=$TERM_SESSION_ID
	# ex: Apple_Terminal_7751E932-9C21-41BC-BFF1-679774179E82.state
	HAG_SESSION_FILE="$HAG_SESSION_DIR/${TERM_PROGRAM}_${HAG_SESSION_ID}.state"
fi

function hag._dehydrate() {
	if [[ -n "$HAG_PURPOSE" ]]; then
		hag.aggregate_shell_history
	fi

	# these should be in place already, but
	# make sure the current state is restorable
	hag._confirm_state_files
}
event on before_exit hag._dehydrate

hag.load_purpose() {
	# file readable by me
	if [ -r "$1" ]; then
		# shellcheck disable=SC1090
		source "$1"
		touch "$1"
	fi

	if [ -z "$HAG_PURPOSE" ]; then
	 	# sourcing the file didn't set a purpose
		return 1
	else
		return 0
	fi
}

function hag._reload_or_set_purpose() {
	if [ -n "$HAG_PURPOSE" ]; then
		# purpose already set
		hag.set_purpose "$1"
	else
		hag.load_purpose "$HAG_DIR/$1/.init" || hag.set_purpose "$1"
	fi
}

function hag._rehydrate() {
	hag.load_purpose "$HAG_SESSION_FILE"

	# If this didn't yield a purpose name, we want to force one.
	if [ -z "$HAG_PURPOSE" ]; then
		read -rp ":( hag doesn't have a purpose; please set one: " purpose
		hag._reload_or_set_purpose "${purpose:-unset}"
		hag._load_shell_history
	fi
}

function hag._tidy()
{
	find "$HAG_SESSION_DIR" -depth -type f -name "*.state" -mtime +14 -delete
}

function hag(){
	case "$1" in
		purpose)
			# TODO: there's probably a logic hole here wrt to purpose changes in a *running* shell.
			# I think my intent is that it'd swap out your history for the one of the new purpose
			# but this means it should probably save/aggregate the histfile for your previous purpose before it loads the new one
			hag._reload_or_set_purpose "$2"
			hag._load_shell_history
			;;
		regenerate)
			hag._reload_shell_history_from_db
			;;
		*)
			printf "\nThe hag profile plugin adds the following subcommands:\n"
			printf "   %s\n      %s\n" "purpose <name>" "Set the purpose"
			printf "   %s\n      %s\n" "regenerate" "Re-generate the current histfile from the hag database."
			printf "      %s\n" "(histfile: $HISTFILE)."
			;;
	esac
}
export hag # TODO: I'm not sure if this is necessary for subshells or if I was just trying to publish it for the preflight script... need to test

function hag._confirm_state_files() {
	# dirs outputs tilde-relative path; +0 == current
	# shellcheck disable=SC2155
	local relpwd="$(dirs +0)"
	mkdir -p "$HAG_SESSION_DIR" "$HAG_PURPOSE_DIR"
	if [ ! -e "$HAG_PURPOSE_INIT_FILE" ]; then
		echo "hag.set_purpose '$HAG_PURPOSE'" >> "$HAG_PURPOSE_INIT_FILE"
	fi
	# replace space with '\ '
	echo "cd ${relpwd// /\\ }" > "$HAG_PURPOSE_PWD_FILE"
	ln -fs "$HAG_PURPOSE_INIT_FILE" "$HAG_SESSION_FILE"
}

function hag.set_purpose() {
	export HAG_PURPOSE="$1"
	export HAG_PURPOSE_DIR="$HAG_DIR/$HAG_PURPOSE"
	export HAG_PURPOSE_INIT_FILE="$HAG_PURPOSE_DIR/.init"
	export HAG_PURPOSE_PWD_FILE="$HAG_PURPOSE_DIR/.pwd"

	HISTFILE="$HAG_PURPOSE_DIR/$HAG_SESSION_ID.$HAG_SHELL"

	if [ -r "$HAG_PURPOSE_PWD_FILE" ]; then
		# shellcheck disable=SC1090
		source "$HAG_PURPOSE_PWD_FILE"
	fi

	hag._confirm_state_files
	_set_terminal_title "$HAG_PURPOSE"
}

function hag.aggregate_shell_history() {
	history -a
}

function hag._reload_shell_history_from_db(){
	history -c # empty current history
	hag._load_shell_history_from_db
	hag._overwrite_histfile_with_loaded_history
}

function hag._load_shell_history_from_db(){
	# shellcheck disable=SC2155
	local tmphist=$(mktemp)
	# TODO: hardcoded limit; this should be based on HISTSIZE
	sqlite3 "file:${HAG_DB}?mode=ro" '.separator "\n"' ".once $tmphist" "select ran_at, entered_cmd from (select start_time, duration, '#'||substr(start_time,1,length(start_time)-6) as ran_at, entered_cmd from log where purpose='$HAG_PURPOSE' and start_time IS NOT NULL order by start_time DESC, duration DESC limit 500) as recent order by start_time ASC, duration ASC"
	history -r "$tmphist"
	((__HAG_PREV_CMD_NUM=HISTCMD-1))
}

function hag._overwrite_histfile_with_loaded_history(){
	history -w
}

function hag._load_shell_history() {
	history -r
	((__HAG_PREV_CMD_NUM=HISTCMD-1))

	# there's no history loaded yet; let's see if it's worth trying to synthesize
	# shellcheck disable=SC2053
	if [[ 0 == $__HAG_PREV_CMD_NUM ]]; then
		# if there are shell history files, let's generate history
		if compgen -G "$HAG_PURPOSE_DIR/*.$HAG_SHELL" > /dev/null; then
			hag._load_shell_history_from_db
		fi
	fi
}

function hag._make_history_file() {
	local command=${1}

	local cmd_hist_file="$HAG_PURPOSE_DIR/$HAG_SESSION_ID.$command"

	touch "$cmd_hist_file"

	echo "$cmd_hist_file"
}

# TODO: debugging "flow" in here is a bit painful. A map of how all this works will pay dividends... (a decent time to do this is during the public/private API rename/refactor)
function hag.add_command_hooks(){
	__shellswain_command_init_hook "$1" hag._init_command "${@:2}"
}

# TODO: better document how all of this pass magick works
# TODO: all basically the same function, maybe simplify the API and pass a specifier?
function hag.pass_per_command(){
	for name in "${@:2}"; do
		event on "hag:vars:command:$1" "hag.passable.$name" "$1"
	done
}
function hag.pass_pre_invocation(){
	for name in "${@:2}"; do
		event on "hag:vars:pre_invocation:$1" "hag.passable.$name" "$1"
	done
}
function hag.pass_post_invocation(){
	for name in "${@:2}"; do
		event on "hag:vars:post_invocation:$1" "hag.passable.$name" "$1"
	done
}

# PER COMMAND
# TODO: I guess some alias or eval ~metaprogramming might be
#       able to DRY some of the boilerplate around these (and
#       the corresponding evals, like in: hag.hook.pre_cmd() {
#         eval "$1"
#         eval "$(event emit "hag:vars:pre_invocation:$2")"
#         ...
function hag.passable.command_path(){
	# shellcheck disable=SC2155
	local command_path=$(type -P "$1")
	local -p # echo these vars for export
}

function hag.passable.history_files(){
	local command_history_file="$HOME/.$1_history"
	# shellcheck disable=SC2155
	local out_history_file=$(hag._make_history_file "$1" "$command_history_file")
	local -p # echo these vars for export
}

function hag.passable.python_vars(){
	# history works a little weird for python
	# python didn't have a history file until 3.5
		# TODO: CONFIRM! ABOVE BASED ON CODE, BUT I DID HAVE A COMMENT STATING: .python_history file use starts in 3.4
	# - python2 can use .python2_history
	# - python3 < 3.5 can use .python3_history
	# - python3 > 3.5 is rudely forced to use .python_history
	# shellcheck disable=SC2155
	local version=$(command "$1" --version 2>&1)

	# TODO: I hate using grep for this; write the bash-only (expansion pattern matching maybe?) replacement at some point--just not super urgent
	# I think: [[ "Python 3.5.4" =~ Python.(2|3.[0-4]) ]]; echo $?
	# but this isn't under test, so I'll resist the urge to fiddle atm.
	if echo "$version" | grep -E "Python (2|3.[0-4])" > /dev/null; then
		# python version <=3.4
		local wrap_command=1
	fi

	if [[ -n "$wrap_command" ]]; then
		# python version <=3.4
		local command_history_file="$HOME/.python${version: 7:1}_history"
	else
		# python version >3.4
		local command_history_file="$HOME/.python_history"
	fi

	# shellcheck disable=SC2155
	local out_history_file=$(hag._make_history_file "$1" "$command_history_file")
	local -p # echo these vars for export
}
function hag.passable.sqlite3_vars(){
	local command_history_file="$HOME/.sqlite_history"
	# shellcheck disable=SC2155
	local out_history_file=$(hag._make_history_file "$1" "$command_history_file")
	local -p # echo these vars for export
}

function hag.passable.pre_command_timing(){
	# shellcheck disable=SC2154
	local start_time="${shellswain[start_time]}"
	local start_timestamp="${shellswain[start_timestamp]}"
	local -p # echo these vars for export
}

function hag.passable.post_command_timing(){
	# shellcheck disable=SC2154
	local duration="${shellswain[duration]}"
	local end_time="${shellswain[end_time]}"
	local end_timestamp="${shellswain[end_timestamp]}"
	local -p # echo these vars for export
}

# <command> <prehook> <runner> <posthook>
# TODO: upgrade pre/post to default callbacks instead of making every caller specify? (true? blank?)
# $1  = command
# $2  = function or "none"
# $3  = function or "none"
# $4  = function or "none"
# $5+ = real cmd args
function hag._init_command(){
	# shellcheck disable=SC2155
	local bundled=$(event emit "hag:vars:command:$1")
	if [[ "$2" != "none" ]]; then
		__swain_phase_listen "before" "$1" "$2" "$bundled" "$1"
	fi

	if [[ "$3" != "none" ]]; then
		__swain_phase_listen "run" "$1" "$3" "$bundled" "$1" "${@:5}"
	fi

	if [[ "$4" != "none" ]]; then
		__swain_phase_listen "after" "$1" "$4" "$bundled" "$1"
	fi
}

function hag.aggregator.nix-shell(){
	# no pre/post to skip meta for now at least; I don't think bash will enjoy the meta cruft I'm adding
	# TODO: test above assumption :]
	hag.add_command_hooks "nix-shell" none nix_shell_run none
	hag.pass_per_command "nix-shell" command_path
}

# $1 will be python, python2, python3, python3.7, etc.
function hag.aggregator.python(){
	hag.add_command_hooks "$1" hag.hook.pre_cmd hag.hook.run_cmd hag.hook.post_cmd

	hag.pass_per_command "$1" command_path python_vars
	hag.pass_pre_invocation "$1" pre_command_timing
	hag.pass_post_invocation "$1" post_command_timing
}

function hag.aggregator.sqlite3(){
	hag.add_command_hooks "$1" hag.hook.pre_cmd none hag.hook.post_cmd

	hag.pass_per_command "$1" command_path sqlite3_vars
	hag.pass_pre_invocation "$1" pre_command_timing
	hag.pass_post_invocation "$1" post_command_timing
}
function hag.aggregator.generic(){ # php, psql
	hag.add_command_hooks "$1" hag.hook.pre_cmd none hag.hook.post_cmd

	hag.pass_per_command "$1" command_path history_files
	hag.pass_pre_invocation "$1" pre_command_timing
	hag.pass_post_invocation "$1" post_command_timing
}
function hag.aggregator.fix_title(){ # ssh, weechat
	hag.add_command_hooks "$1" none none hag.reset_title
}
function hag.reset_title(){
	_set_terminal_title "$HAG_PURPOSE"
}

function nix_shell_run(){
	# shellcheck disable=SC2086
	eval "$1"

	# The way I've broken everything down by .config/hag/<purpose>/<id>.<command> means that whether you call these <termid|command_hash>.<nix-shell|bash>, the *normal* structural expectation is for the history to get saved under its purpose (and, therefore, to have separate per-purpose history). I see 3 outs:
	# 1 .config/hag/.nix-shell/<hash>
	# 2 .config/hag/<purpose>/<termid|command_hash>.<nix-shell|bash>
	# 3 prevent it from saving a file, and synthesize one from the db (but this is back around to needing to persist the nix-shell linkage/hash in the db somewhere)
	# Going with #1 for now; it's the simplest to implement while keeping nix-shell history that isn't isolated per purpose
	# Addenda: I forgot about *bare* commands which will use a shell.nix to load the environment; for those we'll hash the path so that they get their own "space" as it were.
	local to_hash="${*:3}"
	if [[ -z "$to_hash" ]]; then
		to_hash="${PWD}"
	fi

	# shellcheck disable=SC2034
	read -r hash __filename < <(md5sum <<< "${to_hash}")
	HISTFILE="$HAG_DIR/.nix-shell/$hash" command "$command_path" --keep HAG_SESSION_ID --keep HAG_SESSION_FILE --keep HAG_PURPOSE --keep HAG_PURPOSE_DIR --keep HISTFILE "${@:3}"
	# append --keep HISTFILE to make sure it works for pure shells (though unless it can be double-invoked, it may be tricky to parse/massage)
	# TODO: this works, but in pure mode we lose:
	# - history timestamps
	# - the term/tab ID
	# - the hag purpose (I'm not certain hag should re-run inside...)
	# - probably some other related features we might actually want to drag in with us.
	#
	# One approach is explicitly passing it all in;
	# another might be hacking correct settings into .bashrc if we're in a nix shell (though, admittedly, that's making installation harder...);
	# another might be backing off if --pure is present?

	# So there are 3 basic models:
	# 1. don't try
	# 2. make hag back off, except to specify the histfile/timestamp settings,
	# 3. fully bootstrap hag to directly capture the history
	#
	# apart from *methods*, let's focus on goals:
	# - make sure this doesn't overwrite the outer-history with the inner-history
	# - have a separate, durable history space within nix-shell. but by what parameters?
	# 	- path
	# 	- purpose
	# 	- termid
	#   - actual command text? (maybe a hash or base64 of it?)

	# everything I currently have collected:
	# nix-shell --pure
	# nix-shell --help
	# nix-shell -K
	# nix-shell --pure --show-trace
	# nix-shell --version
	# nix-shell -p heroku -p postgresql
	# nix-shell -p wireshark
	# nix-shell -p uwsgi
	# nix-shell -p yq
	# nix-shell -p yadm
	# nix-shell -p android-file-transfer-linuux
	# nix-shell -p android-file-transfer-linux
	# nix-shell -p android-file-transfer
	# nix-shell -p heroku
	# nix-shell -p socat
	# nix-shell -p heroku -p postgres
	# nix-shell -p hyperfine
	# nix-shell --pure -p heroku -p postgresql
	# nix-shell -p litecli

	# I think I've found a razor decision here:
	# command hash is the simplest defensible (clear, nonmagic, etc.) decision
	# - it may miss some purpose-idiomatic context, but it seems like the best all-around way to give the user a high-confidence hit of history that shows how to run the command
	# - near/mid intent to cut active history length
	# 	- cutting history length reduces load time, file size, and really deep scrollback searches are a bit of a misfeature (a UI/X trap!)
	# - longer-term intent to have a history search command
	#
	# CAVEATS/COUNTERPOINTS:
	# 1. hash cmd slower than pure bash underscore subst
	# 2. The underscore method leaves some breadcrumbs as to where/what it came from (i.e., it's obviously a nix-shell from a path). I think this might be why I've kept path this long even though it's weird.
	# 	How, in the hash method, can you cross-correlate a nix history with the command that started the shell?
	# 		a. Save enough context (termid, purpose, etc.) to isolate the individual tab/window that created it and just use the chronology to figure out how we got there
	# 			- could be a correlation text file, or could go in the db maybe
	#			- limited ability to stuff this in the history file in a key-value format like I've done with others unless I use comments to hide them from history (but, making parsing them back out harder).
	#		b. hash all of the nix-shell commands and see what matches
	#		c. explicitly save (whether in the file system or in the database) a nix-shell histfile and the command that created it
	#			I think the main thing I'd need is to expand the export to catch new tables?

	# there's a missing element here. I'm a little embarassed about not seeing it.
	# nix-shell is just bash. I want to save the history. And I want to have these micro-histories, but:
	# - I probably don't need to care about mapping the shell to the file for history purposes. The commands should still go into the command log as bash commands (unless I give nix-shell a distinct table)
	# - But I probably *DO* need to think about whether I can/should preserve enough retroactive information to tell that the command was run in this-or-that nix-shell.
	#	I guess this could be a more general thought about any bash sub-shell; should it be somehow associated with the command that created it?
	# 		I'm not sure there's a huge value to capture here, but I guess if you tracked shell-level and the termid you could notice (and even post-hoc reconstruct) when the level goes up/down as a result of a command, but you'd have to keep these in the database if you want to be able to do it post-hoc, and you'd have to generate an ID the moment you notice it to fix-up the history at the time.
	#		In theory you could post-hoc reconstruct this in most cases via the command log with some heuristics, but they probably have to have the whole nix-shell sequence in-frame to be able to identify it.
	#			Is this a real important thing? From here it seems like the main thing that matters is being able to see/nav the recent history while in the shell. In what othre ways might distinguishing be material?
	#				It might be more obvious why there's a rando commando that you don't hve installed
	#				I guess you might want to be able to query for all commands run in a nix-shell, or all commands run in a specific nix-shell command (even if it has paged out of the local histfile)
	#					IF YOU REPRODUCE AT THIS LEVEL there are a few options available. expand the context of the existing log table so that you can have fields that identify a nix sheell or more generic subshell uniquely or by command OR have something like 2 more tables, 1 listing nix-shell-sessions (log_id, termid, purpose), and another mapping commands from the log into it like cmd_id, nix_shell_session_id
	# * if I get all of the bash lines into the log, and the primary place they live is the log, I can probably reconstruct anything I care about wrt to individual sessions with heuristics or manual tagging later...
}

# curry args *by name* (indirection) instead of value
hag._curry_phase_args(){ # <phase> <command> [<argname>]
	local -a to_curry
	for i in "${@:3}"; do
		to_curry+=("$i=${!i}")
	done
	__swain_curry_phase_args "$1" "$2" "${to_curry[@]}"
}

# TODO: document the variable preconditions for the next 3 functions
# at least command_history_file and out_history_file here (though it also unsets command_path?)
function hag.hook.pre_cmd() {
	eval "$1"
	eval "$(event emit "hag:vars:pre_invocation:$2")"

	touch "$command_history_file"
	local start_history_lines _hag_junkfile
	# shellcheck disable=SC2034,SC2162
	read start_history_lines _hag_junkfile <<< "$(wc -l "$command_history_file")"
	((start_history_lines+=1))

	# curry start_history_lines to the after_<command> hook
	# Yes, start_history_line is not a variable here. Later, it'll be expanded with indirection.
	hag._curry_phase_args "after" "$2" start_history_lines

	_tmp=$out_history_file
	unset command_history_file command_path out_history_file _hag_junkfile start_history_lines

	# pop off the serialized first arg
	# leaves command itself in $@
	# TODO: document this
	shift 1
	{
		printf "%s\n" "===" "shell_session_id=${HAG_SESSION_ID@Q}" "pid=${PPID@Q}" "pwd=${PWD@Q}"
		# shellcheck disable=SC2145
		echo "command='$@'"
		local
	} >> "$_tmp"
	unset _tmp
}

function hag.hook.run_cmd() {
	eval "$1"

	if [[ -n "$wrap_command" ]]; then
		# r(ead)l(ine)wrap lets us inject history where it wasn't. It may cause problems.
		rlwrap --always-readline -H "$command_history_file" "$command_path" "${@:3}"
	else
		# TODO: figure out if command is essential here? It'll prevent hag from wrapping a function (but also, figure out if that's good/bad/neutral?)
		command "$2" "${@:3}"
	fi
}

function hag.hook.post_cmd() {
	eval "$1"
	eval "$3"
	eval "$(event emit "hag:vars:post_invocation:$2")"

	printf "%s\n" "end_time=${end_time@Q}" "end_timestamp=${end_timestamp}" "duration=${duration}" "===" >> "$out_history_file"

	tail -q -n +"${start_history_lines}" "$command_history_file" >> "$out_history_file"
	return $?
}

function hag._record_history(){
	# When the command number is the same (at least, during normal runs), it means we've entered an ignored command! So we'll ignore it. ignored commands may include:
	# - duplicates ignored by HISTCONTROL=ignoredups
	# - space-prefixed commands ignored by HISTCONTROL=ignorespace
	# - anything matched by HISTIGNORE
	#
	# TODO: this heuristic likely misses edge cases around first commands, history loading, etc.
	# shellcheck disable=SC2053
	if [[ ${shellswain[command_number]} == $__HAG_PREV_CMD_NUM ]]; then
		return 1 # TODO: more specific exit codes?
	fi

	__HAG_PREV_CMD_NUM=${shellswain[command_number]}

	# NOTES:
	# - last field is echoed from a subshell (without quoting in the subshell!) to force shell expansion (so we record the command as-entered, *and* what it expanded to match @ runtime!)
	# - above is a small lie when a globbed command created or removed files that match the glob, but I guess I feel like this is a small enough fraction of invocations to shrug off?
	# - last 2 fields have space around quotes to keep python from breaking on commands that start/end with a single quote
	# TODO: I guess the command expansion and tracking of the "expanded" command could be conditional, which would save performance and database size (especially if they frequently run commands with big globs...), but the database schemas would be incompatible, so I think at minimum it would be a *build* option, not a runtime one.
	# shellcheck disable=SC2116,SC2086
	printf '["%s","%s",%d,%d,"%s",'"r''' %s ''',r''' %s ''']\n"  "${HAG_PURPOSE}" "${PWD}" "${shellswain[start_timestamp]}" "${shellswain[duration]}" "${shellswain[pipestatus]}" "${shellswain[command]}" "$(echo ${shellswain[command]})" >> "$HAG_PIPE"
}

function hag._should_record_history()
{
	# TODO: bashup is leaking through, here; am I fine with that or should this be a swain API?
	event on after_command hag._record_history
}

# TODO: Not actually in use yet; this would be used
# by a command that declares a purpose should no-longer
# be recorded.
function hag._should_not_record_history()
{
	# TODO: bashup is leaking through, here; am I fine with that or should this be a swain API?
	event off after_command hag._record_history
}

# If there's no purpose, rehydrate
# (which will load one, or force the user to set)
# If the purpose IS set, we've been passed in vars
# and need to back off to avoid overwriting.
if [[ -z "$HAG_PURPOSE" ]]; then
	hag._rehydrate
fi

# If this isn't set, record history like normal
if [[ -z "$HAG_SHOULD_NOT_RECORD_HISTORY" ]]; then
	hag._should_record_history
fi

# TODO: I probably need a scaffold for defining all interesting versions of python based on the ones that are on the path? Or I guess I can just make the user specify which ones to wrap. That might mean, in practice, that hag knows how to track everything below, but that my user profile has the actual list of commands that triggers it to add them?
# I guess in python's case this could also be some slightly more efficient spec format that can do just python, python(2|3), and python(2|3).(\d+)?
# TODO: at _some_ point, _some_ portion of the statements below and the callback methods should move out of this file (on the latter, I'm not sure how 'officially' hag should support specific commands?) This might be a plugin system?
hag.track "nix-shell" hag.aggregator.nix-shell
hag.track "python" hag.aggregator.python
hag.track "python2" hag.aggregator.python
hag.track "python3" hag.aggregator.python
hag.track "sqlite3" hag.aggregator.sqlite3
hag.track "psql" hag.aggregator.generic
hag.track "php" hag.aggregator.generic
hag.track "ssh" hag.aggregator.fix_title
hag.track "weechat" hag.aggregator.fix_title
