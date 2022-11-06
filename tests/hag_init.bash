#!/usr/bin/env bash

export HOME=home
mkdir -p $HOME

# fake session id
export TERM_PROGRAM=testterm TERM_SESSION_ID=testid

(
	[[ -z "$HAG_PURPOSE" ]] && echo "no initial purpose"

	expect <<-EOF
		spawn -noecho bash --norc --noprofile -c "source hag.bash '$PWD/.config/hag'"
		expect ":( hag doesn't have a purpose; please set one:" {
			send -- "porpoise\r"
			expect "porpoise\r\n" {
				expect "\u001b]1;porpoise\u0007\u001b]2;\u0007" {
					expect "^Should hag track the history for purpose 'porpoise'? " {
						send -- "y\r"
						expect "y\r\n$" {
							expect "hag is tracking history$" {
								expect eof
							}
						}
					}
				}
			}
		}

	EOF

	[[ -e .config/hag/porpoise/.init ]] && echo ".init file created"
)

(
	# "purpose" via .init file now
	source hag.bash "$PWD/.config/hag"

	echo ""

	# shouldn't exist until we exit
	[[ "$HAG_PURPOSE" == "porpoise" ]] && echo "purpose restored from .init"
)
