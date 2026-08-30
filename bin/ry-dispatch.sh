#!/usr/bin/env bash
# Dispatch an engine: create a siding (git worktree) for one task and record
# its meta, status and waybill under state/. Launching the engine in a backend
# is the next step (RY_BACKEND); with RY_BACKEND=none this only lays track.
#
# usage: ry-dispatch.sh (--haul|--survey) [--mode local-only|pr|no-mistakes] <project> <waybill>
# prints: id=<id> and siding=<path>
set -euo pipefail
# shellcheck source=bin/ry-lib.sh
. "$(dirname "$0")/ry-lib.sh"

shape="" mode="" project="" waybill=""
while [ $# -gt 0 ]; do
  case $1 in
    --haul)   shape=haul ;;
    --survey) shape=survey ;;
    --mode)   mode=${2:-}; shift ;;
    -h|--help) sed -n '2,7p' "$0"; exit 0 ;;
    --*)      ry_die "unknown flag $1" ;;
    *) if [ -z "$project" ]; then project=$1; else waybill=$1; fi ;;
  esac
  shift
done

[ -n "$shape" ]   || ry_die "need --haul or --survey"
[ -n "$project" ] || ry_die "need <project>"
[ -n "$waybill" ] || ry_die "need <waybill>"
case $shape in
  haul)   mode=${mode:-local-only}
          case $mode in local-only|pr|no-mistakes) ;; *) ry_die "bad --mode '$mode'";; esac ;;
  survey) [ -z "$mode" ] || [ "$mode" = none ] || ry_die "--mode does not apply to --survey"
          mode=none ;;
esac

home=$(ry_home)
pdir=$(ry_project_dir "$project")
base=$(ry_default_branch "$pdir")
id=$(ry_new_id "$project")
siding="$home/yard/$project/$id"
branch="ry/$id"

git -C "$pdir" fetch -q origin "$base"
mkdir -p "$home/yard/$project" "$home/state"
git -C "$pdir" worktree add -q -b "$branch" "$siding" "origin/$base"

cat > "$home/state/$id.meta" <<META
id=$id
project=$project
shape=$shape
mode=$mode
base=$base
branch=$branch
siding=$siding
created=$(date -u +%Y-%m-%dT%H:%M:%SZ)
META
printf '%s\n' "$waybill" > "$home/state/$id.waybill.md"
ry_set_status "$id" dispatched

printf 'id=%s\nsiding=%s\n' "$id" "$siding"
