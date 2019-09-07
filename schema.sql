CREATE TABLE IF NOT EXISTS log (
    -- low/no variety
    user TEXT, -- cached here
    hostname TEXT, -- cached here
    -- all remaining via pipe
    -- little variety
    purpose TEXT,
    pwd TEXT,
    -- much variety
    start_time INTEGER, -- this might be the PK?
    duration INTEGER,
    pipestatus TEXT, -- space-delimited ints (single for basic commands, multiple with pipes)
    entered_cmd TEXT,
    expanded_cmd TEXT,

    -- not inserted; changed later on export
    exported INTEGER NOT NULL DEFAULT 0,
    -- <name> <type> [PRIMARY KEY ][NOT NULL ][DEFAULT <value> ][CHECK][UNIQUE]
    PRIMARY KEY (start_time, entered_cmd)
    -- FOREIGN KEY (contact_id) REFERENCES contacts (contact_id)
    -- ON DELETE CASCADE ON UPDATE NO ACTION,
); -- may want WITHOUT ROWID; worth testing! https://www.sqlite.org/withoutrowid.html

-- CREATE TABLE commands ();
-- tables/views/indexes:
-- distinct abstract commands as entered
--   - annotations could go here?
-- distinct executables
--   - annotations could go here?
-- annotations as a table keyed against others?
