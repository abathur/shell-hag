#! /usr/bin/env nix-shell
#! nix-shell -I nixpkgs=/Users/abathur/.nix-defexpr/channels/nixpkgs -i bash -p python3 -p sqlite
# shellcheck shell=bash

HAG_SRC="$1"
HAG_DATA_DIR="$2"

HAG_SCHEMA="$HAG_SRC/schema.sql"
HAG_EXPORT_DIR="$HAG_DATA_DIR/.exported"
HAG_NEXT_EXPORT_FILE="$HAG_EXPORT_DIR/$(uuidgen).sql"

export HAG_DB="$HAG_DATA_DIR/.db.sqlite3"
export HAG_PIPE="$HAG_DATA_DIR/.pipe"

function _hag_load_schema_and_data()
{
	echo ".read $HAG_SCHEMA";
	# echo ".echo on"; # for debugging SQL errors
	for f in "$HAG_EXPORT_DIR"/*.sql; do
	    [ -e "$f" ] && echo ".read $f"
	done
}

function _hag_start_daemon()
{
	mkdir -p "$HAG_DATA_DIR/.sessions" "$HAG_EXPORT_DIR"
	mkfifo "$HAG_DATA_DIR/.pipe"
	@sqlite@ "$HAG_DB" \
	".mode insert log" \
	".once $HAG_NEXT_EXPORT_FILE" \
	"SELECT user,hostname,purpose,pwd,start_time,duration,pipestatus,entered_cmd,expanded_cmd,TRUE FROM log WHERE exported IS NOT TRUE order by start_time" \
	"UPDATE log SET exported=TRUE WHERE exported IS NOT TRUE"
	# TODO: this can produce an empty file if there are no commands to export; be cautious since there are consequences for getting it wrong, but add code to detect an empty file here (and log it), and as long as there are never false positives, start manually removing them.
	rm "$HAG_DB"
	@sqlite@ "$HAG_DB" < <(_hag_load_schema_and_data)
	exec "$HAG_SRC/daemon.py"
}

# It's tempting to do some of the startup work on shutdown, but I tried using an exit trap here and it doesn't seem like we get control back between when the python daeemon is forced to stop and when this file is forced to stop.
# It might be possible to do it in the python, but it's probably safest all around, in either case, to do it on startup if startup is at all acceptable.


_hag_start_daemon
