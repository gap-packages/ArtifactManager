#!/bin/sh
#
# ArtifactManager: what is there to work on.
#
#     make tasks
#
# Reads dev/tasks/ in the working tree. A task is ready when every id in its
# `needs` has moved to dev/tasks/done/; otherwise it is blocked, and by what.
# Plain sh so that a GAP package does not grow a tooling dependency for the
# sake of a listing.

cd "$(dirname "$0")/.." || exit 1
[ -d dev/tasks ] || { echo "  no dev/tasks/ here"; exit 1; }

field() { sed -n "s/^$2: *//p" "$1" | head -1; }

# by id rather than by name, or 10 sorts before 2
files=$(ls dev/tasks/[0-9]*.md 2>/dev/null | sort -t/ -k3 -n)
[ -n "$files" ] || { echo "  nothing open"; exit 0; }

# every id still open, for the blocker test below
open_ids=" $(for f in $files; do field "$f" id; done | tr '\n' ' ') "

ready=""; blocked=""
for f in $files; do
    id=$(field "$f" id)
    title=$(field "$f" title)
    needs=$(field "$f" needs | tr -d ' ' | tr ',' ' ')
    wait_on=""
    for n in $needs; do
        case $open_ids in *" $n "*) wait_on="$wait_on $n" ;; esac
    done
    line=$(printf '%4s  %s' "$id" "$title")
    if [ -n "$wait_on" ]; then
        on=$(echo "$wait_on" | sed 's/^ //; s/ /, /g')
        blocked="$blocked$line\n      waiting on $on\n"
    else
        ready="$ready$line\n"
    fi
done

[ -n "$ready" ] && { echo; echo "ready"; printf "$ready"; }
[ -n "$blocked" ] && { echo; echo "blocked"; printf "$blocked"; }
echo
echo "done: $(ls dev/tasks/done/[0-9]*.md 2>/dev/null | wc -l | tr -d ' ')   \
detail: dev/tasks/<id>-*.md"
