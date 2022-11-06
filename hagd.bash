#!/usr/bin/env bash

HAG_SRC="$1"
HAG_DATA_DIR="$2"

HAG_SCHEMA="$HAG_SRC/share/schema.sql"
HAG_EXPORT_DIR="$HAG_DATA_DIR/.exported"
HAG_NEXT_EXPORT_FILE="$HAG_EXPORT_DIR/$(uuid).sql"

export HAG_DB="$HAG_DATA_DIR/.db.sqlite3"
export HAG_DB_IMPORTED="$HAG_DATA_DIR/.db.imported"
export HAG_PIPE="$HAG_DATA_DIR/.pipe"

function _hag_load_schema_and_data()
{
	echo ".read $HAG_SCHEMA";
	# echo ".echo on"; # for debugging SQL errors
	for f in "$HAG_EXPORT_DIR"/*.sql; do
		if [ -e "$f" ]; then
			echo ".read $f"
			echo "$f" >> "$HAG_DB_IMPORTED"
		fi
	done
}

function _hag_set_up_data_dir()
{
	mkdir -p "$HAG_DATA_DIR/.sessions" "$HAG_DATA_DIR/.nix-shell" "$HAG_EXPORT_DIR"
	mkfifo "$HAG_DATA_DIR/.pipe"
	{
		echo "# caution: generated; edits not preserved!"
		echo ".gitignore"
		echo ".db.*"
		echo ".nix-shell/*"
	} > "$HAG_DATA_DIR/.gitignore"
}

function _hag_export_new_history()
{
	# TODO: this can produce an empty file if there are no commands to export; be cautious since there are consequences for getting it wrong, but add code to detect an empty file here (and log it), and as long as there are never false positives, start manually removing them.
	sqlite3 "$HAG_DB" \
	".mode insert log" \
	".once $HAG_NEXT_EXPORT_FILE" \
	"SELECT user,hostname,purpose,pwd,start_time,duration,pipestatus,entered_cmd,expanded_cmd,TRUE FROM log WHERE exported IS NOT TRUE order by start_time" \
	"UPDATE log SET exported=TRUE WHERE exported IS NOT TRUE"
	echo "$HAG_NEXT_EXPORT_FILE" | sort -m -o "$HAG_DB_IMPORTED" "$HAG_DB_IMPORTED" -
}

function _hag_unimported_export_files()
{
	# echo ".echo on"; # for debugging SQL errors
	for f in $(comm -13 "$HAG_DB_IMPORTED" <(ls "$HAG_EXPORT_DIR/"*.sql)); do
		if [ -e "$f" ]; then
			local appended=true
			echo ".read $f"
			echo "$f" >> "$HAG_DB_IMPORTED"
		fi
	done
	[[ "$appended" ]] && sort -o "$HAG_DB_IMPORTED" "$HAG_DB_IMPORTED"
}

function _hag_import_unimported_export_files()
{
	# TODO: not going to sweat it much for now, but this is a lot slower than it needs to be (but still under 100ms) because it calls sqlite whether there's anything to do or not.
	# This doesn't apply to the rebuild command--that one *always* has to run to set up the schema
	sqlite3 "$HAG_DB" < <(_hag_unimported_export_files)
}

function _hag_rebuild_database()
{
	rm "$HAG_DB" "$HAG_DB_IMPORTED" 2>/dev/null
	sqlite3 "$HAG_DB" < <(_hag_load_schema_and_data)
}

# I want to come up with a good routine for cleaning up old state files, but this isn't it. Since I support merging state files from multiple systems and terminals. I think this can/should wait until I implement a good flow for do-not-track since those are the primary source of this pressure anyways
# function _hag_tidy()
# {
# 	find "$HAG_SESSION_DIR" -depth -type l -name "*.state" -mtime +14 -delete
# }

function _hag_start_daemon()
{
	_hag_set_up_data_dir

	if [[ -e "$HAG_DB" && -e "$HAG_DB_IMPORTED" ]]; then
		# Caution: this was above the if block; moved to fix a test but not 100% sure
		_hag_export_new_history
		_hag_import_unimported_export_files
	else
		_hag_rebuild_database
	fi

	exec libexec/daemon.py
}



# It's tempting to do some of the startup work on shutdown, but I tried using an exit trap here and it doesn't seem like we get control back between when the python daemon is forced to stop and when this file is forced to stop.
# It might be possible to do it in the python, but it's probably safest all around, in either case, to do it on startup if startup is at all acceptable.


_hag_start_daemon
