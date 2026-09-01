#!/usr/bin/env bash
# Couple an engine to a siding: create the worktree for a queued task and start
# the engine. Split out of ry-dispatch.sh so a task can be queued now and cut
# later, once whatever it waits on has landed.
#
# The siding is cut from the base branch as the clone sees it *now*, not from a
# ref chosen at queue time — that is the whole point of waiting.
#
# usage: ry-couple.sh <id>
# env:   RY_BACKEND=tmux|orca|none
set -euo pipefail
# shellcheck source=bin/ry-lib.sh
. "$(dirname "$0")/ry-lib.sh"
# shellcheck source=bin/ry-backend-lib.sh
. "$(dirname "$0")/ry-backend-lib.sh"
case ${1:-} in -h|--help) ry_usage "$0"; exit 0 ;; esac

ry_require git jq
id=${1:-}; [ -n "$id" ] || ry_die "need <id>"
home=$(ry_home)
[ "$(cat "$home/state/$id.status" 2>/dev/null || true)" = queued ] \
  || ry_die "$id is not queued; only a queued task can be coupled"

ry_backend_no_split

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

# Before the engine — or any start script it runs — can reach ddev, give the
# siding its own DDEV project name. Silent no-op for a project without .ddev/.
prefix=$(ry_meta_get "$id" prefix); [ -n "$prefix" ] || prefix=${id##*-}
if ! ddev_name=$(ry_ddev_write_override "$siding" "$project" "$prefix"); then
  # Nothing half-cut: undo the worktree so the task stays queued and can be
  # coupled again once the project's .gitignore is fixed.
  git -C "$pdir" worktree remove --force "$siding" 2>/dev/null || true
  git -C "$pdir" worktree prune
  git -C "$pdir" branch -q -D "$branch" 2>/dev/null || true
  exit 1
fi

ry_set_status "$id" dispatched

# The project's own setup, if it has any: fixtures/<project>/ exists whether or
# not anything uses it, so a start script can rely on it and simply find it
# empty. A failure never blocks the dispatch -- the engine launches anyway,
# told plainly that setup failed and that repairing it is not its job, and the
# yardmaster gets an inbox line so it is visible without polling.
ry_fixture_dir "$project" >/dev/null
rm -f "$home/state/$id.setup-failed.md"
start_rc=0
ry_run_start_script "$id" "$siding" "$project" || start_rc=$?
if [ "$start_rc" -ne 0 ]; then
  ry_start_failure_notice "$id" "$ry_start_outcome" > "$home/state/$id.setup-failed.md"
  ry_event "$id" "start-script-failed $ry_start_outcome; output in state/$id.start.log"
  # stderr, so it survives ry-dispatch.sh sending this script's stdout to
  # /dev/null: a dispatch that quietly opened onto a broken environment is the
  # one thing this must not do.
  printf 'start-script=failed (%s); see state/%s.start.log\n' "$ry_start_outcome" "$id" >&2
fi

if [ "$(ry_backend)" != none ]; then
  "$(dirname "$0")/ry-engine-launch.sh" "$id" >/dev/null
fi
printf 'coupled %s to %s (from %s)\n' "$id" "$siding" "$start"
[ -z "$ddev_name" ] || printf 'ddev=%s\n' "$ddev_name"
