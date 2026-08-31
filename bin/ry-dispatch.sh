#!/usr/bin/env bash
# Dispatch a task: record its meta, status and waybill under state/, then hand
# it to ry-couple.sh to cut the siding and start the engine.
#
# With --after the task is only queued: no siding, no engine. It waits until
# something couples it, so its siding is cut after its blockers have landed.
#
# usage: ry-dispatch.sh (--haul|--survey) [--mode local-only|pr]
#                       [--base <branch>] [--after <id>[,<id>...]]
#                       [--prefix <token>] <project> <waybill>
# The base branch comes from --base, else the project's data/projects.md line,
# else develop when the project has one, else the remote's default branch.
# --prefix is one word (a ticket number, say) naming this siding's DDEV
# project: the siding gets name <prefix>-<project> so it never clashes with
# another siding or your own checkout. Defaults to the task id's suffix, and
# means nothing for a project without .ddev/.
# prints: id=<id>, base=<branch> and siding=<path>
set -euo pipefail
# shellcheck source=bin/ry-lib.sh
. "$(dirname "$0")/ry-lib.sh"
# shellcheck source=bin/ry-backend-lib.sh
. "$(dirname "$0")/ry-backend-lib.sh"

shape="" mode="" base="" after="" prefix="" prefix_set=0 project="" waybill=""
while [ $# -gt 0 ]; do
  case $1 in
    --haul)   shape=haul ;;
    --survey) shape=survey ;;
    --mode)   mode=${2:-}; shift ;;
    --base)   base=${2:-}; shift ;;
    --after)  after=${2:-}; shift ;;
    --prefix) prefix=${2:-}; prefix_set=1; shift ;;
    -h|--help) ry_usage "$0"; exit 0 ;;
    --*)      ry_die "unknown flag $1" ;;
    *) if [ -z "$project" ]; then project=$1; else waybill=$1; fi ;;
  esac
  shift
done

[ -n "$shape" ]   || ry_die "need --haul or --survey"
[ -n "$project" ] || ry_die "need <project>"
[ -n "$waybill" ] || ry_die "need <waybill>"
# Validate before anything is written: a bad prefix would only surface as a
# DDEV project that refuses to start, long after dispatch.
[ "$prefix_set" -eq 0 ] || ry_prefix_valid "$prefix" \
  || ry_die "bad --prefix '$prefix': one token matching ^[A-Za-z0-9][A-Za-z0-9-]*$ (a ticket number or one short word)"
case $shape in
  haul)   mode=${mode:-local-only}
          case $mode in
            local-only|pr) ;;
            # Deliver through the no-mistakes git proxy, which is not
            # installed here: accepted once and implemented by nothing
            # downstream, so the task could be dispatched and then never
            # delivered. See docs/prd.md#future-plans.
            no-mistakes) ry_die "--mode no-mistakes needs the no-mistakes tool, which is not wired in: nothing can deliver it. Use local-only or pr." ;;
            *) ry_die "bad --mode '$mode' (local-only|pr)" ;;
          esac ;;
  survey) [ -z "$mode" ] || [ "$mode" = none ] || ry_die "--mode does not apply to --survey"
          mode=none ;;
esac

ry_require git jq
ry_backend_check; ry_backend_no_split
home=$(ry_home)
pdir=$(ry_project_dir "$project")
git -C "$pdir" fetch -q origin
[ -n "$base" ] || base=$(ry_project_base "$project")
git -C "$pdir" rev-parse --verify -q "refs/remotes/origin/$base" >/dev/null \
  || ry_die "base branch '$base' does not exist on origin for project '$project'"

for dep in ${after//,/ }; do
  [ -f "$home/state/$dep.meta" ] || [ -f "$home/state/archive/$dep/meta" ] \
    || ry_die "unknown blocker id '$dep'"
  case $(ry_status_of "$dep") in
    merged) ;;
    *) [ -f "$home/state/$dep.status" ] \
         || ry_die "blocker '$dep' was decoupled without merging; nothing can queue behind it" ;;
  esac
done

id=$(ry_new_id "$project")
# No prefix given: the id already ends in a random token unique to this task.
[ -n "$prefix" ] || prefix=${id##*-}
siding="$home/yard/$project/$id"
branch="ry/$id"

mkdir -p "$home/state"
cat > "$home/state/$id.meta" <<META
id=$id
project=$project
shape=$shape
mode=$mode
base=$base
branch=$branch
siding=$siding
prefix=$prefix
created=$(date -u +%Y-%m-%dT%H:%M:%SZ)
META
[ -n "$after" ] && printf 'after=%s\n' "$after" >> "$home/state/$id.meta"
printf '%s\n' "$waybill" > "$home/state/$id.waybill.md"
ry_set_status "$id" queued

printf 'id=%s\nbase=%s\nsiding=%s\n' "$id" "$base" "$siding"
if [ -n "$after" ]; then
  printf 'status=queued after=%s\n' "$after"
else
  "$(dirname "$0")/ry-couple.sh" "$id" >/dev/null
fi
