#!/usr/bin/env bash
# shellcheck shell=bash

# Not a given that it'll *stay* this way, but the current goal is for this to be a standalone script that doesn't really depend on config (which implies that it either has very basic default behavior, or that it forces the user to disambiguate)

__hag_import_histfiles(){
	case $(smenu -2 ^Y -1 ^N -3 ^C -s /^N -m "Would you like to add these commands to an existing purpose? (if NO, they'll be added to the 'unset' purpose)" <<< "YES NO CANCEL") in
		YES)
			PURPOSE=$(sed -n "s/^hag purpose '\(.*\)'$/\1/p" ~/.config/hag/.sessions/*.state | sort -u | smenu -d -t 4)
			if [ -z "$PURPOSE" ]; then
				return # no-op, they canceled!
			fi
			;;
		NO)
			PURPOSE="unset"
			;;
		*)
			return
			;;
	esac

	for file in "$@"; do
		__hag_import_histfile "$file"
	done
}
__hag_import_histfile(){
	# shellcheck disable=SC2155
	local c_time=$(stat -c "%Y" "$1")
	# shellcheck disable=SC2155
	local first_time=$(sed -n '/^#[0-9]*$/{p;q}' "$1")
	first_time=${first_time:1}
	(( prepend_time=first_time < c_time ? first_time : c_time ))

	# shellcheck disable=SC2155
	local temp="$(mktemp)"
	{
		echo "#$prepend_time"
		cat "$1"
	} > "$temp"

	HISTTIMEFORMAT="%s " HISTSIZE=-1 history -r "$temp"

	# use sed to strip out the command number
	# purpose, pwd, start_timestamp, duration, pipestatus, entered_cmd, expanded_cmd
	HISTTIMEFORMAT="%s " HISTSIZE=-1 history | sed -n "s/^[[:space:]]*[[:digit:]]*[[:space:]]*\([[:digit:]]*\)[[:space:]]*\(.*\)/['$PURPOSE',None,\1000000,None,None,r''' \2 ''',None]/p" # >> "$HAG_PIPE"
	# 1562723766727909,1726
	# 1538838292000000
	# 1562723702825900,2422
	# now we have to actually try and make some magic to insert these
	# one possibility is writing values onto the pipe like the regular script does (though we might compose one big block and drop them all on the pipe at once? or we could do it one by one? high chance of this breaking the existing setup :D)
	#printf '[None,None,%d,None,None,'"'''%s''',None]\n" "${shellswain[start_timestamp]}" "${shellswain[command]}"  >> "$HAG_PIPE"
	history -c # clear
	# sort by time?
	# history | sort -k 2
}

#__hag_import_histfiles ${@:2}
__hag_import_histfiles "${@:2}" >> "$1"
#echo GAH: $HAG_PURPOSE $HAG_PIPE
