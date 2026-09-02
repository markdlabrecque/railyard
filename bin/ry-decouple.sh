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

ry_collapse_data() {  # <home> <project> <id>: fold data/<id>/ into data/<project>/
  local home=$1 project=$2 id=$3 src dest f rel
  src="$home/data/$id"; dest="$home/data/$project"
  [ -d "$src" ] || return 0
  # Same name, same directory: it already is the project folder. Leave it.
  [ "$src" != "$dest" ] || return 0
  # .DS_Store is Finder noise, not work product: it is the one file dropped.
  find "$src" -name .DS_Store -type f -delete
  # Two passes: refuse before anything moves, so a collision leaves data/<id>/
  # whole and the decouple untouched, rather than half-emptied.
  while IFS= read -r -d '' f; do
    rel=${f#"$src"/}; rel=${rel//\//-}
    [ ! -e "$dest/$id-$rel" ] || ry_die "data/$project/$id-$rel already exists; data/$id/ left in place"
  done < <(find "$src" -type f -print0)
  while IFS= read -r -d '' f; do
    [ -d "$dest" ] || mkdir -p "$dest"
    rel=${f#"$src"/}; rel=${rel//\//-}
    mv -n "$f" "$dest/$id-$rel"
  done < <(find "$src" -type f -print0)
  # Empty subdirectories first, deepest first; then the directory itself.
  find "$src" -depth -mindepth 1 -type d -exec rmdir {} \; 2>/dev/null || true
  rmdir "$src" 2>/dev/null || printf 'note: data/%s/ not empty after collapse, left in place\n' "$id" >&2
}

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
  # The siding's own DDEV project goes with the siding, not after it. The
  # prefix and project let it rebuild the name for a siding cut before
  # railyard wrote overrides, which has .ddev/ and no override file.
  ry_ddev_delete "$siding" "$(ry_meta_get "$id" prefix)" "$project"
  git -C "$pdir" worktree remove --force "$siding"
fi
git -C "$pdir" worktree prune
if [ "$delete_branch" -eq 1 ]; then
  git -C "$pdir" branch -q -D "$branch" 2>/dev/null || true
fi

# data/<id>/ goes with the task (#34). Its files are work product -- a survey
# report, a PR body -- so they are moved, never deleted, into the project's
# durable folder as data/<project>/<id>-<file>: flat and browsable by project,
# and the id prefix is what keeps two surveys' report.md apart. Every move is
# a rename, so a decouple that dies midway has lost nothing. The directory
# itself is only ever rmdir'd, never rm -rf'd: if something unexpected is left
# behind it stays, and the decouple says so. Runs before the outcome line and
# the archive loop, using the $project captured above, not a re-read.
ry_collapse_data "$home" "$project" "$id"

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
