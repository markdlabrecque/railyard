#!/usr/bin/env bash
# Land a local-only haul: fast-forward the project's default branch to the
# engine's ry/<id> branch. Refuses anything that is not a clean ff. Run only
# on the dispatcher's explicit word. --push then pushes the default branch.
# usage: ry-merge-local.sh [--push] <id>
set -euo pipefail
# shellcheck source=bin/ry-lib.sh
. "$(dirname "$0")/ry-lib.sh"
case ${1:-} in -h|--help) ry_usage "$0"; exit 0 ;; esac

push=0 id=""
for a in "$@"; do case $a in --push) push=1;; -*) ry_die "unknown flag $a";; *) id=$a;; esac; done
[ -n "$id" ] || ry_die "need <id>"

project=$(ry_meta_get "$id" project); mode=$(ry_meta_get "$id" mode)
base=$(ry_meta_get "$id" base);       branch=$(ry_meta_get "$id" branch)
siding=$(ry_meta_get "$id" siding);   pdir=$(ry_project_dir "$project")

[ "$mode" = local-only ] || ry_die "mode is '$mode', not local-only; use the PR path"
[ -d "$siding" ] || ry_die "siding $siding missing"
[ -z "$(git -C "$siding" status --porcelain)" ] || ry_die "siding has uncommitted changes; have the engine commit first"
[ -z "$(git -C "$pdir" status --porcelain)" ]   || ry_die "project clone $pdir is dirty"

git -C "$pdir" fetch -q origin "$base"
n=$(git -C "$pdir" rev-list --count "origin/$base..$branch" --)
[ "$n" -gt 0 ] || ry_die "no commits on $branch beyond origin/$base"
git -C "$pdir" merge-base --is-ancestor "origin/$base" "$branch" \
  || ry_die "origin/$base moved ahead; $branch is not a fast-forward. Rebase the siding first."

git -C "$pdir" checkout -q "$base"
git -C "$pdir" merge -q --ff-only "origin/$base"
git -C "$pdir" merge -q --ff-only "$branch"
ry_set_status "$id" merged
printf 'merged %s commit(s) from %s into %s\n' "$n" "$branch" "$base"
if [ "$push" -eq 1 ]; then
  git -C "$pdir" push -q origin "$base"
  printf 'pushed %s to origin\n' "$base"
fi
