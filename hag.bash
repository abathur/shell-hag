# shellcheck shell=bash
if [[ -z "$SHELLSWAIN_ABOARD" ]]; then
	# TODO: doc what this provides?
	# shellcheck disable=SC1091
	source "@shellswain@"
fi

# local copy of this shellswain API function
alias __hag_track=__shellswain_track

shopt -s histappend

# TODO: this is so high up because I feel like it's a bit of a utility func that doesn't really belong in hag but is here because we need a simple expressive way to set it because it's not at all obvious on a naive read unless you've memorized the components...
function __hag_set_title()
{
	echo -n -e "\033]0;" "$@" "\007"
}

# capture the starting shell, sans leading dash if present
HAG_SHELL="${0/-/}"
HAG_DIR=${1:-~/.config/hag}
HAG_SESSION_DIR="$HAG_DIR/.sessions"
# Just Apple Terminal for now. Add new terminals later? Could also make user manually add? Maybe an install step?
HAG_SESSION_ID=$TERM_SESSION_ID;
# ex: Apple_Terminal_7751E932-9C21-41BC-BFF1-679774179E82.state
HAG_SESSION_FILE="$HAG_SESSION_DIR/${TERM_PROGRAM}_${HAG_SESSION_ID}.state"
__HAG_PREV_CMD_NUM=$HISTCMD2
HAG_PIPE="$HAG_DIR/.pipe"

function __hag_dehydrate() {
	if [[ -n "$HAG_PURPOSE" ]]; then
		__haggregate_shell_history
	fi

	if [ ! -e "$HAG_SESSION_FILE" ]; then
		echo "hag purpose '$HAG_PURPOSE'" >> "$HAG_SESSION_FILE"
	fi
}
event on before_exit __hag_dehydrate
# TODO move above alongside other global-scope source-time commands, or keep here for local clarity?

function __hag_rehydrate() {
	if [ -r "$HAG_SESSION_FILE" ]; then
		source "$HAG_SESSION_FILE"
		touch "$HAG_SESSION_FILE"
	fi

	# If this didn't yield a project name, we want to force one.
	if [ -z "$HAG_PURPOSE" ]; then
		local purpose="unset"
		read -rp ":( hag doesn't have a purpose; please set one: " purpose;
		__hag_purpose "$purpose"
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
			__hag_purpose "$2"
			__load_shell_history;
			;;
		tidy)
			__hag_tidy
			;;
		*)
			echo "hag has two subcommands."
			printf "    %-10s - %s\n" "purpose <#>" "Set the purpose"
			printf "    %-10s - %s\n" "tidy" "Expunge old (14d+) sessions"
			;;
	esac
}

function __hag_purpose() {
	export HAG_PURPOSE=$1;
	HAG_PURPOSE_DIR="$HAG_DIR/$HAG_PURPOSE";
	HISTFILE="$HAG_PURPOSE_DIR/$HAG_SESSION_ID.$HAG_SHELL"
	mkdir -p "$HAG_PURPOSE_DIR"
	__hag_set_title "$HAG_PURPOSE";
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
			@sqlite@ "file:$HOME/.config/hag/.db.sqlite3?mode=ro" '.separator "\n"' ".once $tmphist" "select '#'||substr(start_time,1,length(start_time)-6), entered_cmd from log where project='$HAG_PURPOSE' order by start_time ASC limit 500"
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

# TODO: document $2, and what we're doing with the md5sum
function __hag_make_history_file() {
	local command=${1}

	# shellcheck disable=SC2034,SC2162
	read id __filename < <(md5sum "${2}")

	local cmd_hist_file="$HAG_DIR/$HAG_PURPOSE/$HAG_SESSION_ID.$command"

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

	HISTFILE="$HAG_DIR/nix-shell/$(echo "$PWD" | tr / _)" command "$command_path" --keep HISTFILE "${@:3}";
	# append --keep HISTFILE to make sure it works for pure shells (though unless it can be double-invoked, it may be a bitch to parse/massage)
	# TODO: this works, but in pure mode we lose history timestamps and probably some other related features we might actually want to drag in with us. One approach is explicitly passing it all in; another might be hacking correct settings into .bashrc if we're in a nix shell (though, admittedly, that's making installation harder...); another might be just backing off if --pure is present?
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
		@rlwrap@ --always-readline -H "$command_history_file" "$command_path" "${@:3}"
	else
		command "$2" "${@:3}"
	fi
}

function __hag_post_cmd() {
	IFS=$'\n'
	# shellcheck disable=SC2046,SC2086
	local $1 $3 $(event emit "__hag_post_invocation_$2_vars")
	unset IFS

	printf "%s\n" "end_time=${end_time@Q}" "end_timestamp=${end_timestamp@Q}" "duration=${duration@Q}" "===" >> "$out_history_file"

	tail -q -n +${start_history_lines} "$command_history_file" >> "$out_history_file"
	return $?
}

function __hag_record_history(){
	# When the command number is the same (at least, during normal runs, and with history configured not to record back-to-back duplicates), it means we've entered a duplicate command! So we'll ignore it.
	# TODO: this almost inevitably misses some edge cases around first commands, history loading, etc.
	# shellcheck disable=SC2053
	if [[ ${shellswain[command_number]} == $__HAG_PREV_CMD_NUM ]]; then
		return 1 # TODO: more specific exit codes?
	fi

	__HAG_PREV_CMD_NUM=${shellswain[command_number]}

	# NOTE: last field is echoed from a subshell (without quoting in the subshell!) to force shell expansion (so we record the command as-entered, *and* what it expanded to match @ runtime!)
	# TODO: I guess the command expansion and tracking of the "expanded" command could be conditional, which would save performance and database size (especially if they frequently run commands with big globs...), but the database schemas would be incompatible, so I think at minimum it would be a *build* option, not a runtime one.
	# shellcheck disable=SC2116,SC2086
	printf '["%s","%s",%d,%d,"%s",'"'''%s''','''%s''']\n"  "${HAG_PURPOSE}" "${PWD}" "${shellswain[start_timestamp]}" "${shellswain[duration]}" "${shellswain[pipestatus]}" "${shellswain[command]}" "$(echo ${shellswain[command]})" >> "$HAG_PIPE"
}

# TODO: bashup is leaking through, here; am I fine with that or should this be a swain API?
event on after_command __hag_record_history

__hag_rehydrate
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
