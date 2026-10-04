#!/usr/bin/env bash
# https://github.com/rtholmes/rthbin
# version 2026-10-04
#
# Test for o, and for fh, which opens things the same way. Neither is allowed
# to open anything here: a stand-in for open goes first on the PATH and prints
# the arguments it was given instead, so the checks are about what would have
# been opened.
#
# Usage: test/o-test.sh
#
# Each check prints ok or FAIL, with the expected and actual output under a
# FAIL. The script exits non-zero when any check fails.

set -u

bin="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# The stand-in for open. It fails the way open does for one app name, so the
# failure path can be checked too.
cat >"$work/open" <<'EOF'
#!/bin/sh
if [ "${2:-}" = "Missing App" ]; then
	echo "Unable to find application named 'Missing App'" >&2
	exit 1
fi
printf '%s\n' "$@"
EOF
chmod +x "$work/open"
export PATH="$work:$PATH"

failures=0
ALIASES=""

# Runs $bin/$1 with the remaining arguments and O_ALIASES set to $ALIASES,
# leaving its output in $out, its error output in $err, and its exit status
# in $status.
run() {
	local tool="$1"
	shift
	out="$(O_ALIASES="$ALIASES" "$bin/$tool" "$@" 2>"$work/err")"
	status=$?
	err="$(cat "$work/err")"
}

# Checks that $1 is exactly $2, under the name $3.
same() {
	if [ "$1" = "$2" ]; then
		echo "ok   $3"
	else
		echo "FAIL $3"
		echo "     expected:"
		printf '%s\n' "$2" | sed 's/^/       /'
		echo "     got:"
		printf '%s\n' "$1" | sed 's/^/       /'
		failures=$((failures + 1))
	fi
}

# Checks that $1 has a line matching the extended regular expression $2.
has() {
	if printf '%s\n' "$1" | grep -qE -- "$2"; then
		echo "ok   $3"
	else
		echo "FAIL $3: no line matches $2"
		printf '%s\n' "$1" | sed 's/^/       /'
		failures=$((failures + 1))
	fi
}

# Checks that the exit status $1 is $2.
exits() {
	if [ "$1" -eq "$2" ]; then
		echo "ok   $3"
	else
		echo "FAIL $3: exit status was $1, not $2"
		failures=$((failures + 1))
	fi
}

echo "== built-in aliases"
run o vsc .
same "$out" $'-a\nVisual Studio Code\n.' "o vsc . opens the folder in Visual Studio Code"
exits "$status" 0 "and exits 0"
run o chrome https://example.com
same "$out" $'-a\nGoogle Chrome\nhttps://example.com' "o chrome opens the page in Google Chrome"
run o VSC .
same "$out" $'-a\nVisual Studio Code\n.' "aliases ignore case"
run o Preview report.pdf
same "$out" $'-a\nPreview\nreport.pdf' "a name that is not an alias is passed to open as given"
run o vsc "My Folder/file one.txt" --background
same "$out" $'-a\nVisual Studio Code\nMy Folder/file one.txt\n--background' "arguments with spaces, and options, arrive intact"

echo "== O_ALIASES"
ALIASES="ff=Firefox;slack=Slack"
run o FF
same "$out" $'-a\nFirefox' "an alias from O_ALIASES, with entries separated by semicolons"
run o slack
same "$out" $'-a\nSlack' "the second entry too"
run o chrome
same "$out" $'-a\nGoogle Chrome' "the built-in aliases still work alongside them"
ALIASES=$' ff = Firefox \n\n word=Microsoft Word \n'
run o ff
same "$out" $'-a\nFirefox' "entries separated by newlines, with blank lines and spaces around them"
run o word
same "$out" $'-a\nMicrosoft Word' "an app name with spaces in it"
ALIASES="vsc=Cursor"
run o vsc
same "$out" $'-a\nCursor' "an entry in O_ALIASES overrides a built-in alias"
ALIASES=""

echo "== listing and help"
run o -l
same "$out" $'vsc        Visual Studio Code\nchrome     Google Chrome' "o -l lists the built-in aliases"
ALIASES="ff=Firefox;VSC=Cursor"
run o -l
same "$out" $'ff         Firefox\nvsc        Cursor\nchrome     Google Chrome' "o -l puts O_ALIASES first and lists an overridden alias once"
ALIASES=""
run o -h
exits "$status" 0 "o -h exits 0"
has "$out" '^Usage:$' "and prints the usage"
has "$out" 'export O_ALIASES=' "including how to add an alias"
run o
exits "$status" 2 "o with no arguments exits 2"
same "$out" "" "prints nothing on standard output"
has "$err" '^Usage:$' "and the usage on standard error"

echo "== when open fails"
run o "Missing App"
exits "$status" 1 "o exits 1 when open cannot find the app"
has "$err" "^Unable to find application named 'Missing App'$" "open's own message is shown"
has "$err" '^o -l lists the aliases, and o -h says how to add one\.$' "followed by the hint"

echo "== fh"
run fh
same "$out" $'-a\nFinder\n.' "fh opens the current folder in Finder"
run fh "My Folder" ~/Downloads
same "$out" $'-a\nFinder\nMy Folder\n'"$HOME/Downloads" "fh passes folders along, spaces and all"

echo
if [ "$failures" -eq 0 ]; then
	echo "All checks passed."
	exit 0
fi
echo "$failures check(s) failed."
exit 1
