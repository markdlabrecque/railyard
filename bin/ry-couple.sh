#!/usr/bin/env bash
# Couple an engine to a siding: create the worktree for a queued task and start
# the engine. Split out of ry-dispatch.sh so a task can be queued now and cut
# later, once whatever it waits on has landed.
#
# The siding is cut from the base branch as the clone sees it *now*, not from a
# ref chosen at queue time — that is the whole point of waiting.
#
# usage: ry-couple.sh <id>
# env:   RY_BACKEND=tmux|none
set -euo pipefail
# shellcheck source=bin/ry-lib.sh
. "$(dirname "$0")/ry-lib.sh"

id=${1:-}; [ -n "$id" ] || ry_die "need <id>"
home=$(ry_home)
[ "$(cat "$home/state/$id.status" 2>/dev/null || true)" = queued ] \
  || ry_die "$id is not queued; only a queued task can be coupled"

project=$(ry_meta_get "$id" project); base=$(ry_meta_get "$id" base)
branch=$(ry_meta_get "$id" branch);   siding=$(ry_meta_get "$id" siding)
pdir=$(ry_project_dir "$project")

git -C "$pdir" fetch -q origin
git -C "$pdir" rev-parse --verify -q "refs/remotes/origin/$base" >/dev/null \
  || ry_die "base branch '$base' does not exist on origin for project '$project'"

# Prefer the clone's own base branch when it is ahead of origin: a local-only
# haul that was merged but not pushed lives only there.
start="origin/$base"
if git -C "$pdir" rev-parse --verify -q "refs/heads/$base" >/dev/null; then
  if git -C "$pdir" merge-base --is-ancestor "origin/$base" "$base"; then
    start="$base"
  elif ! git -C "$pdir" merge-base --is-ancestor "$base" "origin/$base"; then
    ry_die "local $base has diverged from origin/$base in $pdir; reconcile the clone first"
  fi
fi

mkdir -p "$home/yard/$project"
git -C "$pdir" worktree add -q -b "$branch" "$siding" "$start"
ry_set_status "$id" dispatched

if [ "${RY_BACKEND:-tmux}" != none ]; then
  "$(dirname "$0")/ry-engine-launch.sh" "$id" >/dev/null
fi
printf 'coupled %s to %s (from %s)\n' "$id" "$siding" "$start"
