# shellcheck shell=bash
if [[ -z "$SHELLSWAIN_ABOARD" ]]; then
	# TODO: doc what this provides?
	source shellswain.bash
fi

# local copy of this shellswain API function
alias __hag_track=__shellswain_track

shopt -s histappend

# TODO: this is so high up because I feel like it's a bit of a utility func that doesn't really belong in hag but is here because we need a simple expressive way to set it because it's not at all obvious on a naive read unless you've memorized the components...
function __hag_set_title()
{
	# echo -n -e "\033]0;" "$@" "\007"
	printf '\e]1;%s\a' "$*"
}

# capture the starting shell, sans leading dash if present
HAG_SHELL="${0/-/}"
HAG_DIR=${1:-~/.config/hag}
__HAG_PREV_CMD_NUM=$HISTCMD
export HAG_PIPE="$HAG_DIR/.pipe"
export HAG_SESSION_DIR="$HAG_DIR/.sessions"

# If an outer shell passes HAG_SESSION_ID down to us accept it as-is, and do
# *NOT* attempt to compute other values usually derived from it.
# CAUTION: I am using HAG_SESSION_ID as shorthand for multiple variables that
# all need to be explicitly passed for this not to blow up in your face:
# HAG_SESSION_ID, HAG_SESSION_FILE, HAG_PURPOSE, HISTFILE
if [[ -n "$HAG_SESSION_ID" ]]; then
	__load_shell_history
else
	# Just Apple Terminal for now. Add new terminals later? Could also make user manually add? Maybe an install step?
	HAG_SESSION_ID=$TERM_SESSION_ID;
	# ex: Apple_Terminal_7751E932-9C21-41BC-BFF1-679774179E82.state
	HAG_SESSION_FILE="$HAG_SESSION_DIR/${TERM_PROGRAM}_${HAG_SESSION_ID}.state"
fi

function __hag_dehydrate() {
	if [[ -n "$HAG_PURPOSE" ]]; then
		__haggregate_shell_history
	fi

	# these should be in place already, but
	# make sure the current state is restorable
	__hag_confirm_state_files
}
event on before_exit __hag_dehydrate
# TODO move above alongside other global-scope source-time commands, or keep here for local clarity?

__hag_load_purpose() {
	if [ -r "$1" ]; then
		# shellcheck disable=SC1090
		source "$1"
		touch "$1"
	fi

	if [ -z "$HAG_PURPOSE" ]; then
		return 1
	else
		return 0
	fi
}

function __hag_reload_or_set_purpose() {
	__hag_load_purpose "$HAG_DIR/$1/.init" || __hag_set_purpose "$1"
}

function __hag_rehydrate() {
	__hag_load_purpose "$HAG_SESSION_FILE"

	# If this didn't yield a purpose name, we want to force one.
	if [ -z "$HAG_PURPOSE" ]; then
		read -rp ":( hag doesn't have a purpose; please set one: " purpose;
		__hag_reload_or_set_purpose "${purpose:-unset}"
		__load_shell_history
	fi
}

function __hag_tidy()
{
	find "$HAG_SESSION_DIR" -depth -type f -name "*.state" -mtime +14 -delete
}

function hag(){
	case "$1" in
		purpose)
			# TODO: there's probably a logic hole here wrt to purpose changes in a *running* shell.
			# I think my intent is that it'd swap out your history for the one of the new purpose
			# but this means it should probably save/aggregate the histfile for your previous purpose before it loads the new one
			__hag_reload_or_set_purpose "$2"
			__load_shell_history
			;;
		*)
			printf "\nThe hag profile plugin adds the following subcommands:"
			printf "   %s\n      %s\n" "purpose <name>" "Set the purpose"
			;;
	esac
}
export hag # TODO: I'm not sure if this is necessary for subshells or if I was just trying to publish it for the preflight script... need to test



function __hag_confirm_state_files() {
	mkdir -p "$HAG_PURPOSE_DIR"
	if [ ! -e "$HAG_PURPOSE_INIT_FILE" ]; then
		echo "__hag_set_purpose '$HAG_PURPOSE'" >> "$HAG_PURPOSE_INIT_FILE"
	fi
	echo "cd '$PWD'" > "$HAG_PURPOSE_PWD_FILE"
	ln -fs "$HAG_PURPOSE_INIT_FILE" "$HAG_SESSION_FILE"
}

function __hag_set_purpose() {
	export HAG_PURPOSE="$1"
	export HAG_PURPOSE_DIR="$HAG_DIR/$HAG_PURPOSE"
	export HAG_PURPOSE_INIT_FILE="$HAG_PURPOSE_DIR/.init"
	export HAG_PURPOSE_PWD_FILE="$HAG_PURPOSE_DIR/.pwd"

	HISTFILE="$HAG_PURPOSE_DIR/$HAG_SESSION_ID.$HAG_SHELL"

	if [ -r "$HAG_PURPOSE_PWD_FILE" ]; then
		# shellcheck disable=SC1090
		source "$HAG_PURPOSE_PWD_FILE"
	fi

	__hag_confirm_state_files
	__hag_set_title "$HAG_PURPOSE"
}

function __haggregate_shell_history() {
	history -a
}

function __load_shell_history() {
	history -n
	((__HAG_PREV_CMD_NUM=HISTCMD-1))

	# there's no history loaded yet; let's see if it's worth trying to synthesize
	# shellcheck disable=SC2053
	if [[ 0 == $__HAG_PREV_CMD_NUM ]]; then
		# if there are shell history files, let's generate history
		if compgen -G "$HAG_PURPOSE_DIR/*.$HAG_SHELL" > /dev/null; then
			# shellcheck disable=SC2155
			local tmphist=$(mktemp)
			# TODO: nail down path
			# TODO: decide/settle/document the nix @replacement@ vars?
			# TODO: hardcoded limit; this should be based on HISTSIZE
			sqlite3 "file:$HOME/.config/hag/.db.sqlite3?mode=ro" '.separator "\n"' ".once $tmphist" "select '#'||substr(start_time,1,length(start_time)-6), entered_cmd from log where purpose='$HAG_PURPOSE' order by start_time,duration ASC limit 500"
			history -n "$tmphist"
			((__HAG_PREV_CMD_NUM=HISTCMD-1))
		fi
	fi
}



function trap_usr1(){
	echo "trapped USR1" "$@"
}
function trap_usr2(){
	echo "trapped USR2" "$@"
}

trap trap_usr1 USR1
trap trap_usr2 USR2

# TODO: document $2, and what we're doing with the md5sum?
# TODO: actually, reading closer it looks like this is obsolete. I don't see it used. I think it's vestigial from when I was trying to make a file per command run, not a single stream/log
function __hag_make_history_file() {
	local command=${1}

	# shellcheck disable=SC2034,SC2162
	read id __filename < <(md5sum "${2}")

	local cmd_hist_file="$HAG_PURPOSE_DIR/$HAG_SESSION_ID.$command"

	touch "$cmd_hist_file"

	echo "$cmd_hist_file"
}

# TODO: debugging "flow" in here is a bit painful. A map of how all this works will pay dividends... (a decent time to do this is during the public/private API rename/refactor)
function __hag_add_command_hooks(){
	__shellswain_command_init_hook "$1" __hag_init_command "${@:2}"
}

# TODO: better document how all of this pass magick works
# TODO: all basically the same function, maybe simplify the API and pass a specifier?
# NOTE: if they turn up broken, I quoted ${@:2} in the next 3 functions at shellcheck's insistence
function __hag_pass_per_command(){
	for name in "${@:2}"; do
		event on "__hag_command_$1_vars" "__pass_$name" "$1"
	done
}
function __hag_pass_pre_invocation(){
	for name in "${@:2}"; do
		event on "__hag_pre_invocation_$1_vars" "__pass_$name" "$1"
	done
}
function __hag_pass_post_invocation(){
	for name in "${@:2}"; do
		event on "__hag_post_invocation_$1_vars" "__pass_$name" "$1"
	done
}

# PER COMMAND
function __pass_command_path(){
	# shellcheck disable=SC2155
	local command_path=$(type -P "$1");
	local | xargs printf "%s\n" # echo these vars for export
}

function __pass_history_files(){
	local command_history_file="$HOME/.$1_history"
	# shellcheck disable=SC2155
	local out_history_file=$(__hag_make_history_file "$1" "$command_history_file")
	local | xargs printf "%s\n" # echo these vars for export
}

function __pass_python_vars(){
	# history works a little weird for python
	# python didn't have a history file until 3.5
		# TODO: CONFIRM! ABOVE BASED ON CODE, BUT I DID HAVE A COMMENT STATING: .python_history file use starts in 3.4
	# - python2 can use .python2_history
	# - python3 < 3.5 can use .python3_history
	# - python3 > 3.5 is rudely forced to use .python_history
	# shellcheck disable=SC2155
	local version=$(command "$1" --version 2>&1);

	# TODO: I hate using grep for this; write the bash-only (expansion pattern matching maybe?) replacement at some poin--just not super urgent
	if echo "$version" | grep -E "Python (2|3.[0-4])" > /dev/null; then
		# python version <=3.4
		local wrap_command=1;
	fi

	if [[ -n "$wrap_command" ]]; then
		# python version <=3.4
		local command_history_file="$HOME/.python${version: 7:1}_history"
	else
		# python version >3.4
		local command_history_file="$HOME/.python_history"
	fi

	# shellcheck disable=SC2155
	local out_history_file=$(__hag_make_history_file "$1" "$command_history_file")
	local | xargs printf "%s\n" # echo these vars for export
}
function __pass_sqlite3_vars(){
	local command_history_file="$HOME/.sqlite_history"
	# shellcheck disable=SC2155
	local out_history_file=$(__hag_make_history_file "$1" "$command_history_file")
	local | xargs printf "%s\n" # echo these vars for export
}

function __pass_pre_command_timing(){
	# shellcheck disable=SC2154
	local start_time="${shellswain[start_time]}"
	local start_timestamp="${shellswain[start_timestamp]}"
	local | xargs printf "%s\n" # echo these vars for export
}

function __pass_post_command_timing(){
	# shellcheck disable=SC2154
	local duration="${shellswain[duration]}"
	local end_time="${shellswain[end_time]}"
	local end_timestamp="${shellswain[end_timestamp]}"
	local | xargs printf "%s\n" # echo these vars for export
}

# <command> <prehook> <runner> <posthook>
# TODO: upgrade pre/post to default callbacks instead of making every caller specify? (true? blank?)
# $1  = command
# $2  = function or "none"
# $3  = function or "none"
# $4  = function or "none"
# $5+ = real cmd args
function __hag_init_command(){
	# shellcheck disable=SC2155
	local bundled=$(event emit "__hag_command_$1_vars")
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

function __haggregate_nix-shell(){
	# no pre/post to skip meta for now at least; I don't think bash will enjoy the meta cruft I'm adding
	# TODO: test above assumption :]
	__hag_add_command_hooks "nix-shell" none nix_shell_run none
	__hag_pass_per_command "nix-shell" command_path
}

# $1 will be python, python2, python3, python3.7, etc.
function __haggregate_python(){
	__hag_add_command_hooks "$1" __hag_pre_cmd __hag_run_cmd __hag_post_cmd

	__hag_pass_per_command "$1" command_path python_vars
	__hag_pass_pre_invocation "$1" pre_command_timing
	__hag_pass_post_invocation "$1" post_command_timing
}

function __haggregate_sqlite3(){
	__hag_add_command_hooks "$1" __hag_pre_cmd none __hag_post_cmd

	__hag_pass_per_command "$1" command_path sqlite3_vars
	__hag_pass_pre_invocation "$1" pre_command_timing
	__hag_pass_post_invocation "$1" post_command_timing
}
function __haggregate_generic(){ # php, psql
	__hag_add_command_hooks "$1" __hag_pre_cmd none __hag_post_cmd

	__hag_pass_per_command "$1" command_path history_files
	__hag_pass_pre_invocation "$1" pre_command_timing
	__hag_pass_post_invocation "$1" post_command_timing
}
function __haggregate_fix_title(){ # ssh, weechat
	__hag_add_command_hooks "$1" none none __hag_reset_title
}
function __hag_reset_title(){
	__hag_set_title "$HAG_PURPOSE"
}

function nix_shell_run(){
	# shellcheck disable=SC2086
	local $1 # TODO: this technically needs IFS change to catch everything, but I guess I can also omit it when I *know* we don't have to handle spaces?

	# for ref, old format: HISTFILE="$HAG_DIR/nix-shell/$(echo "$PWD" | tr / _)" command "$command_path" --keep HISTFILE "${@:3}";
	# TODO: this histfile path uses the old format. If you actually write to it, hag will start interpreting nix-shell as a purpose. Which brings up a tricky point. The way I've broken everything down by .config/hag/<purpose>/<id>.<command> means that whether you call these <termid|command_hash>.<nix-shell|bash>, the *normal* structural expectation is for the history to get saved under its purpose (and, therefore, to have separate per-purpose history). I see 3 outs:
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
	HISTFILE="$HAG_DIR/.nix-shell/$hash" command "$command_path" --keep HAG_SESSION_ID --keep HAG_SESSION_FILE --keep HAG_PURPOSE --keep HAG_PURPOSE_DIR --keep HISTFILE "${@:3}";
	# append --keep HISTFILE to make sure it works for pure shells (though unless it can be double-invoked, it may be a bitch to parse/massage)
	# TODO: this works, but in pure mode we lose:
	# - history timestamps
	# - the term/tab ID
	# - the hag purpose (I'm not ceretain hag should re-run inside...)
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
	# - I probably don't need to give a flying fuck about mapping the shell to the file for history purposes. The commands should still go into the command log as bash commands (unless I give nix-shell a distinct table)
	# - But I probably *DO* need to think about whether I can/should preserve enough retroactive information to tell that the command was run in this-or-that nix-shell.
	#	I guess this could be a more general thought about any bash sub-shell; should it be somehow associated with the command that created it?
	# 		I'm not sure there's a huge value to capture here, but I guess if you tracked shell-level and the termid you could notice (and even post-hoc reconstruct) when the level goes up/down as a result of a command, but you'd have to keep these in the database if you want to be able to do it post-hoc, and you'd have to generate an ID the moment you notice it to fix-up the history at the time.
	#		In theory you could post-hoc reconstruct this in most cases via the command log with some heuristics, but they probably have to have the whole nix-shell sequence in-frame to be able to identify it.
	#			Is this a real important thing? From here it seems like the main thing that matters is being able to see/nav the recent history while in the shell. In what othre ways might distinguishing be material?
	#				It might be more obvious why there's a rando commando that you don't hve installed
	#				I guess you might want to be able to query for all commands run in a nix-shell, or all commands run in a specific nix-shell command (even if it has paged out of the local histfile)
	#					IF YOU REPRODUCE AT THIS LEVEL there are a few options available. expand the context of the existing log table so that you can have fields that identify a nix sheell or more generic subshell uniquely or by command OR have something like 2 more tables, 1 listing nix-shell-sessions (log_id, termid, purpose), and another mapping commands from the log into it like cmd_id, nix_shell_session_id
	# * if I get all of the bash lines into the log, and the primary place they live is the log, I can probably reconstruct anything I give some shits about wrt to individual sessions with heuristics or manual tagging later...
}

function __hag_pre_cmd() {
	IFS=$'\n'
	# shellcheck disable=SC2046,SC2086
	local $1 $(event emit __hag_pre_invocation_$2_vars)
	unset IFS

	touch "$command_history_file"
	local start_history_lines _hag_junkfile
	# shellcheck disable=SC2034,SC2162
	read start_history_lines _hag_junkfile <<< "$(wc -l "$command_history_file")"
	((start_history_lines+=1))

	# curry start_history_lines to the after_<command> hook
	# Yes, start_history_line is not a variable here. Later, it'll be expanded with indirection.
	__swain_curry "after" "$2" start_history_lines

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

function __hag_run_cmd() {
	IFS=$'\n'
	# shellcheck disable=SC2086
	local $1
	unset IFS

	if [[ -n "$wrap_command" ]]; then
		# r(ead)l(ine)wrap lets us inject history where it wasn't. It may cause problems.
		rlwrap --always-readline -H "$command_history_file" "$command_path" "${@:3}"
	else
		command "$2" "${@:3}"
	fi
}

function __hag_post_cmd() {
	IFS=$'\n'
	# shellcheck disable=SC2046,SC2086
	local $1 $3 $(event emit "__hag_post_invocation_$2_vars")
	unset IFS

	printf "%s\n" "end_time=${end_time@Q}" "end_timestamp=${end_timestamp}" "duration=${duration}" "===" >> "$out_history_file"

	tail -q -n +${start_history_lines} "$command_history_file" >> "$out_history_file"
	return $?
}

function __hag_record_history(){
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
	# - last 2 fields have space around quotes to keep python from breaking on commands that start/end with a single quote
	# TODO: I guess the command expansion and tracking of the "expanded" command could be conditional, which would save performance and database size (especially if they frequently run commands with big globs...), but the database schemas would be incompatible, so I think at minimum it would be a *build* option, not a runtime one.
	# shellcheck disable=SC2116,SC2086
	printf '["%s","%s",%d,%d,"%s",'"r''' %s ''',r''' %s ''']\n"  "${HAG_PURPOSE}" "${PWD}" "${shellswain[start_timestamp]}" "${shellswain[duration]}" "${shellswain[pipestatus]}" "${shellswain[command]}" "$(echo ${shellswain[command]})" >> "$HAG_PIPE"
}

function __hag_should_record_history()
{
	# TODO: bashup is leaking through, here; am I fine with that or should this be a swain API?
	event on after_command __hag_record_history
}

# TODO: Not actually in use yet; this would be used
# by a command that declares a purpose should no-longer
# be recorded.
function __hag_should_not_record_history()
{
	# TODO: bashup is leaking through, here; am I fine with that or should this be a swain API?
	event off after_command __hag_record_history
}

# If there's no purpose, rehydrate
# (which will load one, or force the user to set)
# If the purpose IS set, we've been passed in vars
# and need to back off to avoid overwriting.
if [[ -z "$HAG_PURPOSE" ]]; then
	__hag_rehydrate
fi

# If this isn't set, record history like normal
if [[ -z "$HAG_SHOULD_NOT_RECORD_HISTORY" ]]; then
	__hag_should_record_history
fi

# TODO: I probably need a scaffold for defining all interesting versions of python based on the ones that are on the path? Or I guess I can just make the user specify which ones to wrap. That might mean, in practice, that hag knows how to track everything below, but that my user profile has the actual list of commands that triggers it to add them?
# I guess in python's case this could also be some slightly more efficient spec format that can do just python, python(2|3), and python(2|3).(\d+)?
# TODO: at _some_ point, _some_ portion of the statements below and the callback methods should move out of this file (on the latter, I'm not sure how 'officially' hag should support specific commands?) This might be a plugin system?
__hag_track "nix-shell" __haggregate_nix-shell
__hag_track "python" __haggregate_python
__hag_track "python2" __haggregate_python
__hag_track "python3" __haggregate_python
__hag_track "sqlite3" __haggregate_sqlite3
__hag_track "psql" __haggregate_generic
__hag_track "php" __haggregate_generic
__hag_track "ssh" __haggregate_fix_title
__hag_track "weechat" __haggregate_fix_title
