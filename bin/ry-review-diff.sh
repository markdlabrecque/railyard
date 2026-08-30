#!/usr/bin/env bash
# Show what an engine did: header, commits since the base branch, and the diff.
# --stat replaces the full diff with a file summary. Warns loudly if the
# siding still has uncommitted work.
# usage: ry-review-diff.sh [--stat] <id>
set -euo pipefail
# shellcheck source=bin/ry-lib.sh
. "$(dirname "$0")/ry-lib.sh"

stat=0 id=""
for a in "$@"; do case $a in --stat) stat=1;; -*) ry_die "unknown flag $a";; *) id=$a;; esac; done
[ -n "$id" ] || ry_die "need <id>"

project=$(ry_meta_get "$id" project); mode=$(ry_meta_get "$id" mode)
base=$(ry_meta_get "$id" base);       siding=$(ry_meta_get "$id" siding)
[ -d "$siding" ] || ry_die "siding $siding missing"
status=$(cat "$(ry_home)/state/$id.status" 2>/dev/null || echo unknown)

range="origin/$base...HEAD"
n=$(git -C "$siding" rev-list --count "$range" -- 2>/dev/null || echo 0)
dirty=$(git -C "$siding" status --porcelain)

printf 'id: %s\nproject: %s\nmode: %s\nstatus: %s\nbase: origin/%s\ncommits: %s\n' "$id" "$project" "$mode" "$status" "$base" "$n"
if [ -n "$dirty" ]; then
  printf '\nWARNING: UNCOMMITTED changes in siding:\n%s\n' "$dirty"
fi
printf '\n--- commits\n'; git -C "$siding" log --oneline "$range" --
printf '\n--- diff\n'
if [ "$stat" -eq 1 ]; then git -C "$siding" diff --stat "$range" --
else git -C "$siding" diff "$range" --; fi
