bats_load_library bats-require
load helpers

# TODO: clearly describe why some of these need unbuffer? or maybe just abstract it out and auto-apply it in all cases for consistency if it doesn't cause trouble?

@test "self-creates appropriate directory structure" {
  require <({
    status 0
    # terminal title emitted by setting a purpose
    line 1 begins $'\E]1;porpoise\a\E]2;\a'
    line 1 ends "hag is tracking history"
    # sanity check created dir
    line 2 ends ".config/hag/.sessions"
  })
} <<CASES
./hag_directories.bash
CASES

@test "records command invocations" {
  require <({
    status 0
    line -1 begins '["porpoise",'
    line -1 ends ",r''' ls ''',r''' ls ''']"
  })
} <<CASES
./hag_track.bash ls
CASES

# this is just documenting reality, not utopia
@test "refuses (via shellswain) to track aliases" {
  require <({
    status 0
    line 2 equals "shellswain doesn't currently track aliases (dern)"
  })
} <<CASES
./hag_track.bash dern
CASES

@test "dehydrate saves histfile on exit" {
  require <({
    status 0
    line -1 equals "ls"
  })
} <<CASES
./hag_dehydrate.bash ls
CASES

@test "rehydrate loads histfile on restart" {
  require <({
    status 0
    line 1 begins $'\E]1;porpoise\a\E]2;\a'
    line 1 ends "hag is tracking history"
    # but history on 2nd load
    line -1 equals "    1  ls nothing"
  })
} <<CASES
unbuffer ./hag_rehydrate.bash ls nothing
CASES


# TODO: this test is a bit slow; not sure if I'm using expect
# optimally?
@test "regenerates history from daemon" {
  require <({
    status 0
    line 5 contains "Should hag track the history for purpose"
    line 5 contains "porpoise"
    line 6 equals $'hag is tracking history\r'
    # line 9 is uname output
    # line 11 is uname -a output
    line 16 equals $'before clear:\r'
    line 17 equals $'history\r'
    line 18 contains $'    1  export'
    line 21 equals $'after clear:\r'
    line 22 equals $'history\r'
    # nothing--we cleared it!
    line 25 equals $'after regenerate:\r'
    line 26 equals $'history\r'
    line 27 ends $'    1  uname\r'
    line 28 ends $'    2  uname -a\r'
  })
} <<CASES
unbuffer ./hag_daemon.bash
CASES


@test "reloads purpose from .init file" {
  require <({
    status 0
    # expect script in this test asserts what hag prints;
    # so we assert what the test + expect print
    line 1 equals "no initial purpose"
    line 4 equals $'hag is tracking history\r'
    line -3 equals ".init file created"
    line -2 equals $'\E]1;porpoise\a\E]2;\a'
    line -1 equals "purpose restored from .init"
  })
} <<CASES
./hag_init.bash ls nothing
CASES
