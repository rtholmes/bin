#!/usr/bin/env bash
# https://github.com/rtholmes/rthbin
# version 2026-10-04
#
# Smoke test for repoStatus. Builds throwaway repos in a temporary directory,
# one for each situation repoStatus reports, then checks what status, pull,
# and push print for them. It needs only git and ssh, and never touches the
# network: every "remote" is a bare repo in the same temporary directory, and
# the one unreachable remote is a port on this machine that nothing answers.
#
# Usage: test/repoStatus-test.sh
#
# Each check prints ok or FAIL. When any check fails, the output it was
# checking is printed at the end, and the script exits non-zero.

set -u

repoStatus="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/repoStatus"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cd "$work" || exit 1

# Keep the user's own git configuration out of it: commit signing, hooks, or
# a different default branch name would change what the repos look like.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com

# Makes a bare repo in remotes/ and a clone of it in repos/$1 with one commit
# pushed, so the clone starts out up to date and clean.
make_repo() {
	git init -q --bare -b main "remotes/$1.git"
	git clone -q "remotes/$1.git" "repos/$1" 2>/dev/null
	git -C "repos/$1" symbolic-ref HEAD refs/heads/main
	commit "$1" "first commit"
	git -C "repos/$1" push -q -u origin main 2>/dev/null
}

# Adds a commit to repos/$1 that appends $2 to the file named $3 (default: file).
commit() {
	echo "$2" >>"repos/$1/${3:-file}"
	git -C "repos/$1" add -A && git -C "repos/$1" commit -q -m "$2"
}

# Adds a commit to the remote of repos/$1 by way of a second clone, so repos/$1
# falls behind once it fetches. The commit appends $2 to the file named $3.
remote_commit() {
	local clone="others/$1"
	rm -rf "$clone"
	git clone -q "remotes/$1.git" "$clone" 2>/dev/null
	echo "$2" >>"$clone/${3:-file}"
	git -C "$clone" add -A && git -C "$clone" commit -q -m "$2" && git -C "$clone" push -q 2>/dev/null
}

mkdir repos remotes others

make_repo clean

make_repo ahead
commit ahead "second commit"
commit ahead "third commit"

make_repo behind
remote_commit behind "remote commit"
git -C repos/behind fetch -q

make_repo diverged
commit diverged "local commit" local-file
remote_commit diverged "remote commit" remote-file
git -C repos/diverged fetch -q

make_repo dirty
echo staged >repos/dirty/new-file && git -C repos/dirty add new-file
echo modified >>repos/dirty/file
touch repos/dirty/u1 repos/dirty/u2

make_repo many-untracked
touch repos/many-untracked/u1 repos/many-untracked/u2 repos/many-untracked/u3 repos/many-untracked/u4
touch repos/many-untracked/u5 repos/many-untracked/u6 repos/many-untracked/u7

make_repo many-ahead
for n in 1 2 3 4 5 6; do commit many-ahead "commit $n"; done

make_repo blocked
remote_commit blocked "remote change to file"
echo "local change" >>repos/blocked/file
git -C repos/blocked fetch -q

make_repo gone
git -C repos/gone checkout -q -b feature
commit gone "feature commit"
git -C repos/gone push -q -u origin feature 2>/dev/null
git -C repos/gone push -q origin --delete feature 2>/dev/null
git -C repos/gone fetch -q -p

make_repo detached
git -C repos/detached checkout -q --detach

git init -q -b main repos/no-upstream
commit no-upstream "only commit"

make_repo unreachable
git -C repos/unreachable remote set-url origin ssh://127.0.0.1:1/nothing.git

failures=0

# Checks that $2 has a line matching the extended regular expression $1, and
# reports the result under the name $3.
expect() {
	if printf '%s\n' "$2" | grep -qE -- "$1"; then
		echo "ok   $3"
	else
		echo "FAIL $3: no line matches $1"
		failures=$((failures + 1))
	fi
}

# Checks that $2 has no line matching $1.
expect_not() {
	if printf '%s\n' "$2" | grep -qE -- "$1"; then
		echo "FAIL $3: a line matches $1"
		failures=$((failures + 1))
	else
		echo "ok   $3"
	fi
}

# Checks that the exit status $1 is $2.
expect_exit() {
	if [ "$1" -eq "$2" ]; then
		echo "ok   $3"
	else
		echo "FAIL $3: exit status was $1, not $2"
		failures=$((failures + 1))
	fi
}

date='[A-Z][a-z]{2} [0-9]{2} [0-9]{2}:[0-9]{2}'

echo "== repoStatus repos"
status="$("$repoStatus" repos 2>&1)"
status_exit=$?
expect '^clean +main +up to date +clean$' "$status" "an up-to-date clean repo"
expect '^ahead +main +ahead 2 +clean$' "$status" "a repo that is ahead"
expect "^ +$date  third commit \(test@example.com\)$" "$status" "unpushed commits are listed"
expect '^behind +main +behind 1 +clean$' "$status" "a repo that is behind"
expect "^ +$date  remote commit \(test@example.com\)$" "$status" "unpulled commits are listed"
expect '^diverged +main +ahead 1, behind 1 +clean$' "$status" "a diverged repo"
expect '^ +pull blocked: main has diverged from origin/main, so it cannot fast-forward$' "$status" "a diverged repo is reported as blocked"
expect '^dirty +main +up to date +1 staged, 1 modified, 2 untracked$' "$status" "staged, modified, and untracked counts"
expect '^ +staged: new-file$' "$status" "the staged file is listed"
expect '^ +modified: file$' "$status" "the modified file is listed"
expect '^ +untracked: u1$' "$status" "the first untracked file is listed"
expect '^ +u2$' "$status" "the next untracked file lines up under it"
expect '^many-untracked +main +up to date +7 untracked$' "$status" "a repo with many untracked files"
expect '^ +u5$' "$status" "the fifth untracked file is listed"
expect_not '^ +u6$' "$status" "the sixth untracked file is not"
expect '^ +\(2 more\)$' "$status" "the rest of the untracked files are counted"
expect '^many-ahead +main +ahead 6 +clean$' "$status" "a repo with many unpushed commits"
expect "^ +$date  commit 2 \(" "$status" "the fifth newest commit is listed"
expect_not "  commit 1 \(" "$status" "the sixth newest commit is not"
expect '^ +\(1 more\)$' "$status" "the rest of the commits are counted"
expect '^blocked +main +behind 1 +1 modified$' "$status" "a repo whose pull would overwrite a change"
expect '^ +pull blocked: uncommitted changes to file would be overwritten$' "$status" "and why its pull is blocked"
expect '^gone +feature +upstream gone +clean$' "$status" "a repo whose upstream branch was deleted"
expect '^detached +detached +detached HEAD +clean$' "$status" "a repo with a detached HEAD"
expect '^no-upstream +main +no upstream +clean$' "$status" "a repo with no upstream"
expect '^unreachable +main +up to date +clean$' "$status" "an unreachable remote is not contacted without -f"
expect '^\(ahead and behind are as of' "$status" "the reminder that nothing was fetched"
expect_not $'\033' "$status" "no colour codes when not writing to a terminal"
expect_exit "$status_exit" 1 "status exits 1 when a pull is blocked"

echo "== repoStatus -f repos"
fetched="$("$repoStatus" -f repos 2>&1)"
fetched_exit=$?
expect '^unreachable +main +up to date +clean$' "$fetched" "the unreachable repo is still reported"
expect '^ +fetch failed: cannot reach 127.0.0.1: the connection was refused$' "$fetched" "and its fetch failure is explained"
expect '^clean +main +up to date +clean$' "$fetched" "the other repos are fetched"
expect_not '^\(ahead and behind are as of' "$fetched" "no reminder after fetching"
expect_exit "$fetched_exit" 1 "status -f exits 1 when a fetch fails"

echo "== repoStatus pull repos"
pulled="$("$repoStatus" pull repos 2>&1)"
pulled_exit=$?
expect '^behind +pulled 1 commit\(s\)$' "$pulled" "the repo that was behind is pulled"
expect '^diverged +failed: main has diverged from origin/main, so it cannot fast-forward$' "$pulled" "the diverged repo fails"
expect '^blocked +failed: uncommitted changes to file would be overwritten$' "$pulled" "the blocked repo fails and says why"
expect '^gone +skipped: upstream origin/feature no longer exists$' "$pulled" "the repo with a gone upstream is skipped"
expect '^detached +skipped: detached HEAD$' "$pulled" "the detached repo is skipped"
expect '^no-upstream +skipped: no upstream$' "$pulled" "the repo with no upstream is skipped"
expect '^unreachable +skipped: cannot reach 127.0.0.1: the connection was refused$' "$pulled" "the unreachable repo is skipped, not failed"
expect_not '^clean ' "$pulled" "an up-to-date repo prints nothing"
expect_not '^ahead ' "$pulled" "a repo that is only ahead prints nothing"
expect_exit "$pulled_exit" 1 "pull exits 1 when a pull fails"
if [ "$(git -C repos/behind rev-parse HEAD)" = "$(git -C remotes/behind.git rev-parse main)" ]; then
	echo "ok   the pulled repo now matches its remote"
else
	echo "FAIL the pulled repo does not match its remote"
	failures=$((failures + 1))
fi

echo "== repoStatus push repos (without -y, and without a terminal)"
asked="$("$repoStatus" push repos 2>&1 </dev/null)"
asked_exit=$?
expect '^ahead: 2 commit\(s\) to push to origin/main$' "$asked" "the repo that is ahead is listed"
expect '^dirty has 1 staged change\(s\) that are not committed, so a push leaves them out\.$' "$asked" "staged changes are pointed out"
expect '^diverged: skipped, main is also behind origin/main, so a push would be rejected\. Pull first\.$' "$asked" "the diverged repo is skipped"
expect '^gone: skipped, origin/feature no longer exists on the remote$' "$asked" "the repo with a gone upstream is skipped"
expect '^detached: skipped, detached HEAD$' "$asked" "the detached repo is skipped"
expect '^no-upstream: skipped, it has no upstream and no origin remote\.$' "$asked" "the repo with no remote is skipped"
expect '^Not pushing without a terminal to confirm; rerun with -y\.$' "$asked" "nothing is pushed without a terminal to ask"
expect_exit "$asked_exit" 1 "and that counts as a failure"
if [ "$(git -C remotes/ahead.git rev-parse main)" != "$(git -C repos/ahead rev-parse HEAD)" ]; then
	echo "ok   the remote was left alone"
else
	echo "FAIL the remote was pushed to without confirmation"
	failures=$((failures + 1))
fi

echo "== repoStatus push -y repos"
pushed="$("$repoStatus" push -y repos 2>&1)"
pushed_exit=$?
expect '^ahead +pushed$' "$pushed" "the repo that is ahead is pushed"
expect '^many-ahead +pushed$' "$pushed" "so is the one with many commits"
expect_exit "$pushed_exit" 0 "push exits 0 when every push works"
if [ "$(git -C remotes/ahead.git rev-parse main)" = "$(git -C repos/ahead rev-parse HEAD)" ]; then
	echo "ok   the remote now has the pushed commits"
else
	echo "FAIL the remote does not have the pushed commits"
	failures=$((failures + 1))
fi

echo "== repoStatus repos, afterwards"
after="$("$repoStatus" repos 2>&1)"
expect '^ahead +main +up to date +clean$' "$after" "the pushed repo is up to date"
expect '^behind +main +up to date +clean$' "$after" "the pulled repo is up to date"

echo
if [ "$failures" -eq 0 ]; then
	echo "All checks passed."
	exit 0
fi
echo "$failures check(s) failed. The output that was checked:"
for name in status fetched pulled asked pushed after; do
	echo
	echo "--- $name"
	printf '%s\n' "${!name}" | sed 's/^/    /'
done
exit 1
