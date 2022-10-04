load helpers

# TODO: abstract out all of this socat cruft

@test "self-creates appropriate directory structure" {
  require <({
    status 0
    # terminal title emitted by setting a purpose
    line 1 equals $'\E]1;porpoise\a'
    # sanity check created dir
    line 2 equals ".config/hag/.sessions"
  })
} <<CASES
socat stdio exec:."/hag_directories.bash",pty,setsid,echo=0,crlf
CASES

@test "records command invocations" {
  require <({
    status 0
    line -1 begins '["porpoise",'
    line -1 ends ",r''' ls ''',r''' ls ''']"
  })
} <<CASES
socat stdio exec:."/hag_track.bash ls",pty,setsid,echo=0,crlf
CASES

# this is just documenting reality, not utopia
@test "refuses (via shellswain) to track aliases" {
  require <({
    status 0
    line 2 equals "shellswain doesn't currently track aliases (dern)"
  })
} <<CASES
socat stdio exec:."/hag_track.bash dern",pty,setsid,echo=0,crlf
CASES

@test "dehydrate saves histfile on exit" {
  require <({
    status 0
    line -1 equals "ls"
  })
} <<CASES
socat stdio exec:."/hag_dehydrate.bash ls",pty,setsid,echo=0,crlf
CASES

@test "rehydrate loads histfile on restart" {
  require <({
    status 0
    # the output tester swallows empty lines, so if the below is line 2--it means there's no history
    line 2 equals "ls: cannot access 'nothing': No such file or directory"
    # but yes history on 2nd load
    line 4 equals "    1  ls nothing"
  })
} <<CASES
socat stdio exec:."/hag_rehydrate.bash ls nothing",pty,setsid,echo=0,crlf
CASES

@test "regenerates history from daemon" {
  require <({
    status 0
    line 1 equals $'\E]1;porpoise\a'
    # line 2 is uname output
    line 3 equals $'\E]1;porpoise\a'
    # but yes history on 2nd load
    line 4 equals "    1  uname"
    # line 5 is uname output
    line 6 equals $'\E]1;porpoise\a'
    line 7 equals "before clear:"
    line 8 equals "    1  uname"
    line 9 equals "    2  uname"
    line 10 equals "after clear:"
    # nothing--we cleared it!
    line 11 equals "after regenerate:"
    line 12 equals "    1  uname"
    line 13 equals "    2  uname"
  })
} <<CASES
socat stdio exec:."/hag_daemon.bash",pty,setsid,echo=0,crlf
CASES


@test "reloads purpose from .init file" {
  require <({
    status 0
    line 1 equals "no initial purpose"
    line 2 equals $'\E]1;porpoise\a'
    line 3 equals ".init file created"
    line 4 equals $'\E]1;porpoise\a'
    line 5 equals "purpose restored from .init"
  })
} <<CASES
socat stdio exec:."/hag_init.bash ls nothing",pty,setsid,echo=0,crlf
CASES
