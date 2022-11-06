#!/usr/bin/env bash

export HOME=.

# fake session id
export TERM_PROGRAM=testterm TERM_SESSION_ID=testid

# database shouldn't exist before starting daemon
if [[ -e .config/hag/.db.sqlite3 ]]; then
	exit 1
fi

hagd.bash "" ".config/hag" &>/dev/null &

# database should exist once the daemon's going
until [[ -e .config/hag/.db.sqlite3 ]]; do
	:
done

initial_commands(){
	expect <<-EOF
		spawn -noecho bash --norc --noprofile
		stty -echo
		send -- "export TERM_PROGRAM=testterm TERM_SESSION_ID=testid PS1='PROMPT>'\r"
		expect "PROMPT>$" {
			send -- "source hag.bash '$PWD/.config/hag'\r"
			expect ":( hag doesn't have a purpose; please set one:" {
				send -- "porpoise\r"
				expect "porpoise\r\n" {
					expect "\u001b]1;porpoise\u0007\u001b]2;\u0007" {
						expect "Should hag track the history for purpose 'porpoise'" {
							send -- "y\r"
							expect "y\r\n"
						}
						expect "hag is tracking history" {
							send -- "uname\r"
							expect "PROMPT>$" {
								send -- "uname -a\r"
								expect "PROMPT>$" {
									send -- "exit\r"
								}
							}
						}
					}
				}
			}
		}
	EOF
}

set -e
initial_commands && [[ "$(sqlite3 -cmd ".timeout 5000" "file:$PWD/.config/hag/.db.sqlite3?mode=ro" "select count(*) from log")" == "2" ]]
set +e

expect <<-EOF
	spawn -noecho bash --norc --noprofile
	stty -echo
	# expect "bash-5.1"
	send -- "export HISTIGNORE='history*:source*' TERM_PROGRAM=testterm TERM_SESSION_ID=testid PS1='PROMPT>'\r"
	expect "PROMPT>$" {
		send -- "source hag.bash '$PWD/.config/hag'\r"
		expect "PROMPT>$" {
			puts ""
			puts "before clear:"
			send -- "history\r"
			expect "PROMPT>$" {
				send -- "history -c\r"
				expect "PROMPT>$" {
					puts ""
					puts "after clear:"
					send -- "history\r"
					expect "PROMPT>$" {
						send -- "hag regenerate\r"
						expect "PROMPT>$" {
							puts ""
							puts "after regenerate:"
							send -- "history\r"
							expect "PROMPT>$" {
								send -- "exit\r"
							}
						}
					}
				}
			}
		}
	}
EOF
