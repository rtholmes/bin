#!/usr/bin/env bash
# https://github.com/rtholmes/rthbin
# version 2026-10-01
#
# rst, for repo status, reports, pulls, or pushes git repos. Run inside a repo,
# it works on that repo. Run anywhere else, it works on every repo directly
# inside the current directory. Directories given as arguments are used instead
# of the current directory, each in the same way, with a heading for each when
# there are several.
#
# Usage:
#   rst              status of each repo, from what git already knows
#   rst -f           fetch first, so the ahead and behind counts are current
#   rst pull         fast-forward each repo that has an upstream
#   rst push         push each repo with commits its upstream does not have
#   rst push -y      push without asking first
#   rst -f ~/a ~/b   any command, for ~/a and ~/b instead of the current directory
#   rst version      the date of this copy of the script
#
# status is the default command. It also names any repo that pull could not
# fast-forward, and why, and exits non-zero when it finds one. pull uses
# --ff-only, so it never creates a merge commit; a repo it cannot fast-forward
# is reported and left alone.
#
# status -f, pull, and push work on up to 8 repos at a time, then print the
# results in order. A remote that needs a password typed in cannot prompt in
# parallel, so its fetch, pull, or push fails and is reported instead of
# waiting. A host that does not answer within 5 seconds, such as one a VPN
# blocks, is reported as unreachable while the other repos carry on; pull skips
# its repos rather than counting them as failures. Any fetch, pull, or push
# still running 60 seconds after it started is stopped and reported.
#
# Under each repo, status lists its unpushed and unpulled commits and its
# untracked files, up to 5 of each, and counts the rest.

set -u

# The version is the date in the header above, so it is only written once.
version="$(sed -n '3s/^# version //p' "$0")"

# Count characters, not bytes, when trimming commit messages, and keep git's
# messages in English so the pull problems below read as expected. Some older
# systems have no C.UTF-8 locale, and asking for one there makes bash warn
# before every command, so on those only git's language is pinned.
if locale -a 2>/dev/null | grep -qiE '^C\.utf-?8$'; then
	export LC_ALL=C.UTF-8
else
	export LC_MESSAGES=C
fi

usage="usage: $(basename "$0") [status] [-f] | pull | push [-y] | help, and optionally directories"

# The command, options, and directories can come in any order, and the command
# defaults to status, so "rst -f" means "rst status -f".
cmd=""
fetch=0
yes=0
dirs=()
for arg in "$@"; do
	case "$arg" in
	status | pull | push | help | version)
		if [ -n "$cmd" ] && [ "$cmd" != "$arg" ]; then
			echo "give one command, not both $cmd and $arg" >&2
			exit 2
		fi
		cmd="$arg"
		;;
	-h | --help) cmd="help" ;;
	--version) cmd="version" ;;
	-f | --fetch) fetch=1 ;;
	-y | --yes) yes=1 ;;
	*)
		if [ -d "$arg" ]; then
			dirs+=("$arg")
		else
			echo "not a command, an option, or a directory: $arg" >&2
			echo "$usage" >&2
			exit 2
		fi
		;;
	esac
done
cmd="${cmd:-status}"

if [ "$cmd" = version ]; then
	echo "rst $version"
	exit 0
fi
if [ "$cmd" = help ]; then
	echo "rst $version"
	sed -n '2,/^$/p' "$0" | sed -e '/^$/d' -e '/^# version /d' -e 's/^# \{0,1\}//'
	exit 0
fi
if [ "$fetch" -eq 1 ] && [ "$cmd" != status ]; then
	echo "-f applies only to status; $cmd always talks to the remote" >&2
	exit 2
fi
if [ "$yes" -eq 1 ] && [ "$cmd" != push ]; then
	echo "-y applies only to push" >&2
	exit 2
fi

if [ -t 1 ]; then
	red=$'\033[31m'
	purple=$'\033[35m'
	yellow=$'\033[33m'
	cyan=$'\033[36m'
	dim=$'\033[2m'
	bold=$'\033[1m'
	off=$'\033[0m'
else
	red="" purple="" yellow="" cyan="" dim="" bold="" off=""
fi

# The repos to work on, and in groups the directory each one came from, shown
# with ~ for the home directory. Each directory contributes the repo it is part
# of, or else every repo directly inside it. A repo reached twice is listed once.
[ ${#dirs[@]} -gt 0 ] || dirs=("$PWD")
repos=()
groups=()
failures=0

# Adds the repo at $1, found in the directory labelled $2, unless it is listed.
add_repo() {
	local listed
	for listed in ${repos[@]+"${repos[@]}"}; do
		[ "$listed" = "$1" ] && return 0
	done
	repos+=("$1")
	groups+=("$2")
}

for given in "${dirs[@]}"; do
	if ! dir="$(cd "$given" 2>/dev/null && pwd)"; then
		echo "${red}cannot enter $given${off}"
		failures=$((failures + 1))
		continue
	fi
	case "$dir" in
	"$HOME" | "$HOME"/*) label="~${dir#"$HOME"}" ;;
	*) label="$dir" ;;
	esac
	found=0
	here="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)"
	if [ -n "$here" ]; then
		add_repo "$here" "$label"
		found=1
	else
		for sub in "$dir"/*/; do
			if [ -e "${sub}.git" ]; then
				add_repo "${sub%/}" "$label"
				found=1
			fi
		done
	fi
	[ "$found" -eq 1 ] || echo "$label is not in a git repo, and has no git repos directly inside it."
done
[ ${#repos[@]} -gt 0 ] || exit "$([ "$failures" -eq 0 ] && echo 0 || echo 1)"

# The directory whose heading was printed last; see heading.
shown_group=""

# Prints the heading for the directory repo number $1 came from, when more than
# one directory was given and it differs from the last heading printed. Set
# shown_group to "" before each list of repos.
heading() {
	[ ${#dirs[@]} -gt 1 ] || return 0
	[ "${groups[$1]}" != "$shown_group" ] || return 0
	[ -z "$shown_group" ] || echo
	shown_group="${groups[$1]}"
	echo "${bold}${shown_group}${off}"
}

# Holds the per-repo results of the parallel fetches, pulls, and pushes, and
# is removed when the script exits.
tmp_dir=""
trap 'if [ -n "$tmp_dir" ]; then rm -rf "$tmp_dir"; fi' EXIT

# SSH settings for fetch, pull, and push. They give up on a host that does not
# answer within 5 seconds, drop a connection that stops responding for 15
# seconds, and fail rather than prompt, so one unreachable host cannot hold up
# the rest. They are not used when GIT_SSH_COMMAND, GIT_SSH, or a repo's
# core.sshCommand already chooses how git runs ssh.
ssh_settings="ssh -o ConnectTimeout=5 -o ServerAliveInterval=5 -o ServerAliveCountMax=3 -o BatchMode=yes"

# Runs git in the repo at $1, with the remaining arguments, for an operation
# that talks to a remote.
remote_git() {
	local repo="$1"
	shift
	if [ -z "${GIT_SSH_COMMAND:-}" ] && [ -z "${GIT_SSH:-}" ] && [ -z "$(git -C "$repo" config core.sshCommand)" ]; then
		GIT_TERMINAL_PROMPT=0 git -C "$repo" -c core.sshCommand="$ssh_settings" "$@"
	else
		GIT_TERMINAL_PROMPT=0 git -C "$repo" "$@"
	fi
}

# How long a fetch, pull, or push may run before it is stopped, in seconds.
deadline=60

# How many fetches, pulls, or pushes run at once. Many more than this at a
# time and a host such as github.com starts dropping connections.
parallel=8

# How many commits, and how many untracked files, are listed under a repo
# before the rest are counted as "(N more)".
max_rows=5

# Stops process $1 and every process under it, such as the ssh that git started.
kill_tree() {
	local child
	for child in $(pgrep -P "$1" 2>/dev/null); do
		kill_tree "$child"
	done
	kill "$1" 2>/dev/null
}

# Runs the function $2 in the background once for each argument after it, up
# to $parallel at a time, and waits for all of them. While they run, and only
# when stderr is a terminal, it shows a spinner with $1 and how many have
# finished, updated every half second, then clears that line. A job still
# running $deadline seconds after it started is stopped, and
# $tmp_dir/timeout.<k> is created, where k is the job's position in the
# argument list, counting from 0.
run_all() {
	local label="$1" job="$2" total running finished k i=0 frames='|/-\'
	local pids=() ticks=()
	shift 2
	total=$#
	while :; do
		# Count the jobs still running, and stop any that has reached its deadline.
		running=0
		for k in ${pids[@]+"${!pids[@]}"}; do
			[ "${pids[$k]}" != 0 ] || continue
			if kill -0 "${pids[$k]}" 2>/dev/null; then
				running=$((running + 1))
				ticks[$k]=$((ticks[$k] + 1))
				if [ "${ticks[$k]}" -gt $((deadline * 2)) ]; then
					touch "$tmp_dir/timeout.$k"
					kill_tree "${pids[$k]}"
				fi
			else
				pids[$k]=0
			fi
		done
		# Start more while there is room and there are jobs left.
		while [ "$running" -lt "$parallel" ] && [ $# -gt 0 ]; do
			"$job" "$1" &
			pids+=($!)
			ticks+=(0)
			shift
			running=$((running + 1))
		done
		finished=$((${#pids[@]} - running))
		[ "$finished" -lt "$total" ] || break
		[ -t 2 ] && printf '\r%s %s: %d of %d done' "${frames:i%4:1}" "$label" "$finished" "$total" >&2
		i=$((i + 1))
		sleep 0.5
	done
	[ -t 2 ] && printf '\r\033[K' >&2
	wait 2>/dev/null
}

# Fetches repo number $1. If the fetch fails, $tmp_dir/$1 gets git's error output.
fetch_job() {
	local out
	if ! out="$(remote_git "${repos[$1]}" fetch --quiet 2>&1)"; then
		printf '%s\n' "$out" >"$tmp_dir/$1"
	fi
}

# Fetches every repo, a few at a time, and waits for all of them.
fetch_all() {
	tmp_dir="$(mktemp -d)"
	run_all "fetching" fetch_job "${!repos[@]}"
}

# Prints the status of the repo at $1 as one line of fields separated by the
# ASCII unit separator, which cannot appear in a path: branch, upstream, ahead,
# behind, staged, modified, untracked, conflicted, the first $max_rows
# untracked paths, every staged path, every modified path, every conflicted
# path, and 1 if git reported ahead and behind counts (0 when the upstream
# branch no longer exists). The path lists are separated by the ASCII record
# separator.
info() {
	git -C "$1" -c core.quotePath=false status --porcelain=v2 --branch 2>/dev/null | awk -v max="$max_rows" '
		# The path follows 8 fixed fields on a "1" line, 10 on a "u" (conflict)
		# line, and 9 on a "2" (rename) line, where a tab then separates it from
		# the original path.
		function path(fields,    line, i) {
			line = $0
			for (i = 0; i < fields; i++) sub(/^[^ ]+ /, "", line)
			sub(/\t.*/, "", line)
			return line
		}
		$2 == "branch.head" { head = $3 }
		$2 == "branch.upstream" { up = $3 }
		$2 == "branch.ab" { ahead = substr($3, 2) + 0; behind = substr($4, 2) + 0; counted = 1 }
		/^[12] / {
			if (substr($2, 1, 1) != ".") {
				staged++
				snames = snames (staged > 1 ? "\036" : "") path($1 == "1" ? 8 : 9)
			}
			if (substr($2, 2, 1) != ".") {
				modified++
				mnames = mnames (modified > 1 ? "\036" : "") path($1 == "1" ? 8 : 9)
			}
		}
		/^u / {
			conflicted++
			cnames = cnames (conflicted > 1 ? "\036" : "") path(10)
		}
		/^\? / {
			untracked++
			if (untracked <= max) unames = unames (untracked > 1 ? "\036" : "") substr($0, 3)
		}
		END {
			printf "%s\037%s\037%d\037%d\037%d\037%d\037%d\037%d\037%s\037%s\037%s\037%s\037%d\n", head, up, ahead, behind, staged, modified, untracked, conflicted, unames, snames, mnames, cnames, counted
		}'
}

# Prints the most useful line of the git error output in $1. An ssh line comes
# first because git's own line after it only says the remote could not be read.
first_error() {
	local line
	line="$(echo "$1" | grep -m1 -E '^ssh: |\[rejected\]|^(error|fatal):')"
	[ -n "$line" ] || line="$(echo "$1" | grep -v '^hint:' | head -1)"
	echo "$line" | sed -e 's/^ *! *//' \
		-e 's/^ssh: connect to host \([^ ]*\) port [0-9]*: Operation timed out.*/cannot reach \1: the connection timed out/' \
		-e 's/^ssh: connect to host \([^ ]*\) port [0-9]*: Connection refused.*/cannot reach \1: the connection was refused/' \
		-e 's/^ssh: Could not resolve hostname \([^:]*\):.*/cannot reach \1: the name does not resolve/' |
		tr -s ' '
}

# Reads info for the repo at $1 into the variables named in info's output.
load() {
	IFS=$'\037' read -r branch upstream ahead behind staged modified untracked conflicted untracked_names staged_names modified_names conflicted_names counted <<<"$(info "$1")"
	# The upstream branch no longer exists on the remote.
	gone=0
	[ -n "$upstream" ] && [ "$counted" -eq 0 ] && gone=1
	detached=0
	[ "$branch" = "(detached)" ] && detached=1 && branch="detached"
}

# Prints why a fast-forward pull of the repo at $1 would fail, or nothing if it
# would succeed. Call load first. It changes nothing: read-tree -n only
# rehearses moving the working tree to the upstream commit.
pull_problem() {
	local gitdir out
	gitdir="$(git -C "$1" rev-parse --absolute-git-dir)"
	if [ -e "$gitdir/MERGE_HEAD" ]; then
		echo "a merge is in progress"
		return
	fi
	if [ -d "$gitdir/rebase-merge" ] || [ -d "$gitdir/rebase-apply" ]; then
		echo "a rebase is in progress"
		return
	fi
	if [ -z "$upstream" ] || [ "$behind" -eq 0 ]; then
		return
	fi
	if [ "$ahead" -gt 0 ]; then
		echo "$branch has diverged from $upstream, so it cannot fast-forward"
		return
	fi
	if ! out="$(git -C "$1" read-tree -n -m -u HEAD '@{u}' 2>&1)"; then
		first_error "$out" | sed -e 's/^error: //' \
			-e "s/^Entry '\(.*\)' not uptodate\. Cannot merge\./uncommitted changes to \1 would be overwritten/" \
			-e "s/^Entry '\(.*\)' would be overwritten by merge\. Cannot merge\./staged changes to \1 would be overwritten/" \
			-e "s/^Untracked working tree file '\(.*\)' would be overwritten by merge\./untracked \1 would be overwritten by an incoming file/"
	fi
}

# Prints one row per commit in range $2 of the repo at $1, such as @{u}..HEAD
# for commits not yet pushed: the commit's local date and time, the first 40
# characters of its subject on one line in colour $3, and the committer's
# email in brackets in the terminal's normal colour. $4 is how many commits
# the range holds; only the newest $max_rows are listed, and a final row
# counts the rest.
commit_rows() {
	local when subject email
	git -C "$1" log -n "$max_rows" --format='%ad%x1f%s%x1f%ce' --date=format-local:'%b %d %H:%M' "$2" |
		while IFS=$'\037' read -r when subject email; do
			subject="${subject//[[:space:]]/ }"
			while [[ "$subject" == *"  "* ]]; do
				subject="${subject//  / }"
			done
			subject="${subject# }"
			subject="${subject:0:40}"
			subject="${subject% }"
			[ -n "$subject" ] || subject="(no message)"
			printf "%-22s %s%s  %s%s (%s)\n" "" "$3" "$when" "$subject" "$off" "$email"
		done
	[ "$4" -le "$max_rows" ] || printf "%-22s %s(%d more)%s\n" "" "$3" "$(($4 - max_rows))" "$off"
}

# Prints the paths in $3, separated by the record separator, one per row in
# colour $2: the first row starts with the label $1, and the rest are indented
# to line up under the first path. A final row $4, if given, is printed the
# same way, for notes such as "(3 more)".
file_rows() {
	local label="$1" color="$2" list="$3" extra="${4:-}" item first=1 pad
	pad="$(printf '%*s' "${#label}" "")"
	while IFS= read -r -d $'\036' item || [ -n "$item" ]; do
		if [ "$first" -eq 1 ]; then
			printf "%-22s %s%s%s%s\n" "" "$color" "$label" "$item" "$off"
			first=0
		else
			printf "%-22s %s%s%s%s\n" "" "$color" "$pad" "$item" "$off"
		fi
	done < <(printf '%s' "$list")
	[ -z "$extra" ] || printf "%-22s %s%s%s%s\n" "" "$color" "$pad" "$extra" "$off"
}

cmd_status() {
	local i repo name sync sync_color changes changes_color fetch_error problem more
	[ "$fetch" -eq 1 ] && fetch_all
	shown_group=""
	for i in "${!repos[@]}"; do
		repo="${repos[$i]}"
		name="$(basename "$repo")"
		heading "$i"
		fetch_error=""
		if [ -n "$tmp_dir" ] && [ -f "$tmp_dir/timeout.$i" ]; then
			fetch_error="no answer after $deadline seconds"
		elif [ -n "$tmp_dir" ] && [ -f "$tmp_dir/$i" ]; then
			fetch_error="$(first_error "$(cat "$tmp_dir/$i")")"
		fi
		load "$repo"

		if [ "$detached" -eq 1 ]; then
			sync="detached HEAD" sync_color="$yellow"
		elif [ -z "$upstream" ]; then
			sync="no upstream" sync_color="$yellow"
		elif [ "$gone" -eq 1 ]; then
			sync="upstream gone" sync_color="$yellow"
		elif [ "$ahead" -eq 0 ] && [ "$behind" -eq 0 ]; then
			sync="up to date" sync_color="$dim"
		else
			sync="" sync_color="$cyan"
			[ "$ahead" -gt 0 ] && sync="ahead $ahead"
			[ "$behind" -gt 0 ] && sync="${sync:+$sync, }behind $behind" sync_color="$purple"
		fi

		changes="" changes_color="$yellow"
		[ "$conflicted" -gt 0 ] && changes="$conflicted conflicted" changes_color="$red"
		[ "$staged" -gt 0 ] && changes="${changes:+$changes, }$staged staged"
		[ "$modified" -gt 0 ] && changes="${changes:+$changes, }$modified modified"
		[ "$untracked" -gt 0 ] && changes="${changes:+$changes, }$untracked untracked"
		[ -z "$changes" ] && changes="clean" changes_color="$dim"

		printf "%-22s %-12s %s%-18s%s %s%s%s\n" "$name" "$branch" "$sync_color" "$sync" "$off" "$changes_color" "$changes" "$off"

		if [ -n "$upstream" ] && [ "$ahead" -gt 0 ]; then
			commit_rows "$repo" '@{u}..HEAD' "$cyan" "$ahead"
		fi
		if [ -n "$upstream" ] && [ "$behind" -gt 0 ]; then
			commit_rows "$repo" 'HEAD..@{u}' "$purple" "$behind"
		fi
		[ "$conflicted" -gt 0 ] && file_rows "conflicted: " "$changes_color" "$conflicted_names"
		[ "$staged" -gt 0 ] && file_rows "staged: " "$changes_color" "$staged_names"
		[ "$modified" -gt 0 ] && file_rows "modified: " "$changes_color" "$modified_names"
		if [ "$untracked" -gt 0 ]; then
			more=""
			[ "$untracked" -gt "$max_rows" ] && more="($((untracked - max_rows)) more)"
			file_rows "untracked: " "$changes_color" "$untracked_names" "$more"
		fi

		if [ -n "$fetch_error" ]; then
			failures=$((failures + 1))
			printf "%-22s %sfetch failed: %s%s\n" "" "$red" "$fetch_error" "$off"
		fi
		problem="$(pull_problem "$repo")"
		if [ -n "$problem" ]; then
			failures=$((failures + 1))
			printf "%-22s %spull blocked: %s%s\n" "" "$red" "$problem" "$off"
		fi
	done
	[ "$fetch" -eq 1 ] || echo "${dim}(ahead and behind are as of each repo's last fetch; use -f to fetch first)${off}"
}

# Pulls the repo at $1 and prints its one-line result. Returns 1 if the pull failed.
pull_one() {
	local repo="$1" name before after out problem
	name="$(basename "$repo")"
	load "$repo"
	if [ "$detached" -eq 1 ]; then
		printf "%-22s %sskipped: detached HEAD%s\n" "$name" "$yellow" "$off"
		return 0
	fi
	if [ -z "$upstream" ]; then
		printf "%-22s %sskipped: no upstream%s\n" "$name" "$yellow" "$off"
		return 0
	fi
	if [ "$gone" -eq 1 ]; then
		printf "%-22s %sskipped: upstream %s no longer exists%s\n" "$name" "$yellow" "$upstream" "$off"
		return 0
	fi
	before="$(git -C "$repo" rev-parse HEAD)"
	if out="$(remote_git "$repo" pull --ff-only --quiet 2>&1)"; then
		after="$(git -C "$repo" rev-parse HEAD)"
		# A repo that was already up to date prints nothing.
		if [ "$before" != "$after" ]; then
			printf "%-22s %spulled %s commit(s)%s\n" "$name" "$cyan" "$(git -C "$repo" rev-list --count "$before..$after")" "$off"
		fi
		return 0
	fi
	# A host that cannot be reached is a skip, not a failure: nothing was changed,
	# and the pull will work once the host is reachable again.
	problem="$(first_error "$out")"
	case "$problem" in
	"cannot reach "*)
		printf "%-22s %sskipped: %s%s\n" "$name" "$yellow" "$problem" "$off"
		return 0
		;;
	esac
	load "$repo"
	printf "%-22s %sfailed: %s%s\n" "$name" "$red" "$(pull_problem "$repo" | grep . || echo "$problem")" "$off"
	return 1
}

# Pulls repo number $1, saving its result line in $tmp_dir/$1.out and creating
# $tmp_dir/$1.failed if the pull failed.
pull_job() {
	pull_one "${repos[$1]}" >"$tmp_dir/$1.out" || touch "$tmp_dir/$1.failed"
}

# Pulls every repo, a few at a time, then prints the results in the usual
# order. Repos that were already up to date are left out, along with any
# heading that would have nothing under it.
cmd_pull() {
	local i shown=0
	tmp_dir="$(mktemp -d)"
	run_all "pulling" pull_job "${!repos[@]}"
	shown_group=""
	for i in "${!repos[@]}"; do
		if [ -f "$tmp_dir/timeout.$i" ]; then
			heading "$i"
			printf "%-22s %sskipped: no answer after %d seconds%s\n" "$(basename "${repos[$i]}")" "$yellow" "$deadline" "$off"
			shown=$((shown + 1))
		elif [ -s "$tmp_dir/$i.out" ]; then
			heading "$i"
			cat "$tmp_dir/$i.out"
			shown=$((shown + 1))
		fi
		[ -f "$tmp_dir/$i.failed" ] && failures=$((failures + 1))
	done
	[ "$shown" -gt 0 ] || echo "${dim}Every repo was already up to date.${off}"
}

# Pushes the repo at $1 and prints its one-line result. Returns 1 if the push failed.
push_one() {
	local name out
	name="$(basename "$1")"
	if out="$(remote_git "$1" push --quiet 2>&1)"; then
		printf "%-22s %spushed%s\n" "$name" "$cyan" "$off"
		return 0
	fi
	printf "%-22s %sfailed: %s%s\n" "$name" "$red" "$(first_error "$out")" "$off"
	return 1
}

# Pushes repo number $1, saving its result line in $tmp_dir/$1.out and creating
# $tmp_dir/$1.failed if the push failed.
push_job() {
	push_one "${repos[$1]}" >"$tmp_dir/$1.out" || touch "$tmp_dir/$1.failed"
}

# Lists what would be pushed, asks unless -y was given, then pushes every
# listed repo, a few at a time, and prints the results in the usual order.
cmd_push() {
	local i k repo name answer
	local to_push=()
	shown_group=""
	for i in "${!repos[@]}"; do
		repo="${repos[$i]}"
		name="$(basename "$repo")"
		load "$repo"
		if [ "$staged" -gt 0 ]; then
			heading "$i"
			echo "${yellow}$name has $staged staged change(s) that are not committed, so a push leaves them out.${off}"
		fi
		if [ "$detached" -eq 1 ]; then
			heading "$i"
			echo "${yellow}$name: skipped, detached HEAD${off}"
			continue
		fi
		if [ -z "$upstream" ]; then
			heading "$i"
			if git -C "$repo" remote get-url origin >/dev/null 2>&1; then
				echo "${yellow}$name: skipped, $branch has no upstream. Push it once with: git -C $repo push -u origin $branch${off}"
			else
				echo "${yellow}$name: skipped, it has no upstream and no origin remote.${off}"
			fi
			continue
		fi
		if [ "$gone" -eq 1 ]; then
			heading "$i"
			echo "${yellow}$name: skipped, $upstream no longer exists on the remote${off}"
			continue
		fi
		if [ "$ahead" -gt 0 ] && [ "$behind" -gt 0 ]; then
			heading "$i"
			echo "${yellow}$name: skipped, $branch is also behind $upstream, so a push would be rejected. Pull first.${off}"
			continue
		fi
		if [ "$ahead" -gt 0 ]; then
			to_push+=("$i")
			heading "$i"
			echo "$name: $ahead commit(s) to push to $upstream"
		fi
	done

	if [ ${#to_push[@]} -eq 0 ]; then
		echo "Nothing to push."
		return
	fi

	if [ "$yes" -eq 0 ]; then
		if [ ! -t 0 ]; then
			echo "Not pushing without a terminal to confirm; rerun with -y." >&2
			failures=$((failures + 1))
			return
		fi
		read -r -p "Push ${#to_push[@]} repo(s)? [y/N] " answer
		case "$answer" in
		y | Y | yes) ;;
		*)
			echo "Nothing pushed."
			return
			;;
		esac
	fi

	tmp_dir="$(mktemp -d)"
	run_all "pushing" push_job "${to_push[@]}"
	[ ${#dirs[@]} -gt 1 ] && echo
	shown_group=""
	k=0
	for i in "${to_push[@]}"; do
		if [ -f "$tmp_dir/timeout.$k" ]; then
			heading "$i"
			printf "%-22s %sfailed: no answer after %d seconds%s\n" "$(basename "${repos[$i]}")" "$red" "$deadline" "$off"
			failures=$((failures + 1))
		elif [ -s "$tmp_dir/$i.out" ]; then
			heading "$i"
			cat "$tmp_dir/$i.out"
		fi
		[ -f "$tmp_dir/$i.failed" ] && failures=$((failures + 1))
		k=$((k + 1))
	done
}

case "$cmd" in
status) cmd_status ;;
pull) cmd_pull ;;
push) cmd_push ;;
esac

[ "$failures" -eq 0 ]
