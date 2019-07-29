#! /usr/bin/env nix-shell
#! nix-shell -I nixpkgs=/Users/abathur/.nix-defexpr/channels/nixpkgs -i python3 -p python3 -p sqlite
from typing import Callable
import os
import platform
import functools
import sqlite3
import argparse
import sys
import ast


CSV_FMT = "pwd,start_time,duration,pipestatus,entered_cmd,expanded_cmd"

insert_command = """
    INSERT INTO log (user,hostname,project,pwd,start_time,duration,pipestatus,entered_cmd,expanded_cmd)
    VALUES (?,?,?,?,?,?,?,?,?)
"""

# TODO: I think daemon.sh handle this from schema.sql
create_tables = """
    CREATE TABLE IF NOT EXISTS log (
        -- low/no variety
        user TEXT, -- cached here
        hostname TEXT, -- cached here
        -- all remaining via pipe
        -- little variety
        project TEXT,
        pwd TEXT,
        -- much variety
        start_time INTEGER, -- this might be the PK?
        duration INTEGER,
        pipestatus TEXT, -- space-delimited ints (single for basic commands, multiple with pipes)
        entered_cmd TEXT,
        expanded_cmd TEXT,

        -- not inserted; changed later on export
        exported INTEGER NOT NULL DEFAULT 0
    ); -- may want WITHOUT ROWID; worth testing! https://www.sqlite.org/withoutrowid.html

    -- CREATE TABLE commands ();
    -- tables/views/indexes:
    -- distinct abstract commands as entered
    --   - annotations could go here?
    -- distinct executables
    --   - annotations could go here?
    -- annotations as a table keyed against others?
    --
"""

# NOTES:
# - this is defined by the nix-darwin launchd service
# - updates will be meaningless without rebuilding nix-darwin config
# TODO: should these have a default? just fall over?

HAG_PIPE = os.environ.get("HAG_PIPE")
USER = os.environ.get("USER")
HOSTNAME = platform.node()


INGESTERS = dict()
Ingester = Callable[[], callable]
DB = None


def chomp_row_v1(
    user,
    hostname,
    project,
    pwd,
    start_time,
    duration,
    pipestatus,
    entered_cmd,
    expanded_cmd,
):
    with DB:
        DB.execute(
            insert_command,
            (
                user,
                hostname,
                project,
                pwd,
                start_time,
                duration,
                pipestatus,
                entered_cmd,
                expanded_cmd.strip(),
            ),
            # TODO this could be optimized
        )


def add_ingester(header: str, ingester: Ingester) -> Ingester:
    curried = functools.partial(ingester, USER, HOSTNAME)
    INGESTERS[header] = curried
    return curried


CURRENT_INGESTER = add_ingester(CSV_FMT, chomp_row_v1)

# TODO: not sure how much work this should do
def ingest_transitfile(transitfile):
    with open(transitfile, "r") as f, csv.reader(f, quotechar="'") as log:
        fields = ",".join(next(x))
        ingester = INGESTERS[fields]
        for line in log:  # 2
            ingester(*line)


def connect_sqlite3():
    return sqlite3.connect(os.environ.get("HAG_DB"))


import traceback

if __name__ == "__main__":

    DB = connect_sqlite3()
    with DB:
        # TODO: I think daemon.sh may handle this now, but I'm not certain how it behaves on a bare start. Confirm behavior here with tests and remove this if possible.
        DB.execute(create_tables)

    try:
        # until the heat-death of the universe:
        # 1. open the pipe, which blocks for input
        #    until someone writes to it
        # 2. exhaust whatever was written, treating each
        #    line as a command
        #    * yes, yes, this may well be a source of errors when commands contain a newline, but let's get it all wired up and working without more fundamental problems before we sweat this *
        # 3. exhausting auto-closes the pipe
        #
        # CAUTION: non-interactive! block-buffered!
        #    *IF WE WRITE TO STDOUT* we have to flush
        #    WE DO FOR DEBUG, BUT CAN RM/DISABLE LATER
        while True:
            with open(HAG_PIPE, "r") as hagpipe:  # 1
                for line in hagpipe:  # 2
                    print("ingesting", line)
                    CURRENT_INGESTER(*ast.literal_eval(line))
            sys.stdout.flush()
    except BaseException as e:
        # DEBUG
        traceback.print_exc()
        print(repr(e))
        sys.stdout.flush()
        raise
    finally:
        # anything critical on shutdown?
        # flushing just in case there's stray debug
        sys.stdout.flush()
