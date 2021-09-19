shell-hag is a bash-based shell-history aggregator

Its long-term aim is to aggregate not just bash history, but also the history of other interactive shells such as REPLs.

Don't depend on it, yet.

It works well enough to live in my own bash profile, but:
- It does some poorly-documented stuff with your history.
- I haven't sorted out how I want to handle public/private APIs yet; I assume I'll end up renaming some or all of the functions.

Hag depends on https://github.com/abathur/shellswain (and thus on bash 5 and https://github.com/bashup/events).
