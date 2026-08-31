#!/usr/bin/env bash
# Decouple an engine: remove its siding (worktree) and archive its state.
# The ry/<id> branch is kept unless --delete-branch. A dirty siding is refused
# unless --force. Stops the engine's terminal first (whatever backend opened it).
#
# usage: ry-decouple.sh [--force] [--delete-branch] <id>
set -euo pipefail
# shellcheck source=bin/ry-lib.sh
. "$(dirname "$0")/ry-lib.sh"
# shellcheck source=bin/ry-backend-lib.sh
. "$(dirname "$0")/ry-backend-lib.sh"

force=0 delete_branch=0 id=""
while [ $# -gt 0 ]; do
  case $1 in
    --force)         force=1 ;;
    --delete-branch) delete_branch=1 ;;
    -h|--help) ry_usage "$0"; exit 0 ;;
    --*) ry_die "unknown flag $1" ;;
    *)   id=$1 ;;
  esac
  shift
done
[ -n "$id" ] || ry_die "need <id>"

home=$(ry_home)
project=$(ry_meta_get "$id" project)
siding=$(ry_meta_get "$id" siding)
branch=$(ry_meta_get "$id" branch)
pdir=$(ry_project_dir "$project")
ry_backend_stop "$id"

if [ -d "$siding" ]; then
  if [ "$force" -eq 0 ] && [ -n "$(git -C "$siding" status --porcelain)" ]; then
    ry_die "siding $siding has uncommitted changes; commit them or pass --force"
  fi
  # The siding's own DDEV project goes with the siding, not after it.
  ry_ddev_delete "$siding"
  git -C "$pdir" worktree remove --force "$siding"
fi
git -C "$pdir" worktree prune
if [ "$delete_branch" -eq 1 ]; then
  git -C "$pdir" branch -q -D "$branch" 2>/dev/null || true
fi

# Preserve the outcome before it is overwritten: whether this task merged is
# what anything queued behind it needs to know.
printf 'outcome=%s\n' "$(ry_status_of "$id")" >> "$home/state/$id.meta"
ry_set_status "$id" decoupled
arch="$home/state/archive/$id"
mkdir -p "$arch"
for f in "$home/state/$id".*; do
  [ -e "$f" ] || continue
  mv "$f" "$arch/${f##*/"$id".}"
done
printf 'decoupled %s\n' "$id"
