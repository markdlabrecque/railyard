#!/usr/bin/env bash
# Dispatch a task: record its meta, status and waybill under state/, then hand
# it to ry-couple.sh to cut the siding and start the engine.
#
# With --after the task is only queued: no siding, no engine. It waits until
# something couples it, so its siding is cut after its blockers have landed.
#
# usage: ry-dispatch.sh (--haul|--survey) [--mode local-only|pr]
#                       [--base <branch>] [--after <id>[,<id>...]]
#                       [--ticket <n>] [--slug <text>] [--prefix <token>]
#                       <project> <waybill>
# The waybill's first line is the task's title: at most 80 characters, a short
# imperative summary of the whole task, with a blank line 2 and the body from
# line 3. bin/ry-pr.sh uses it verbatim as the PR/MR title, so a longer first
# line is refused here rather than by the forge after the branch is pushed.
# The id is the name of the work: <ticket>-<slug> with a ticket, the slug alone
# without one. --ticket is the issue or pull/merge request number (a leading
# hash is fine) and defaults to the first ticket reference in the waybill's
# first line; --slug is a short description and defaults to that same line.
# Both are slugified the same dumb way, so --slug "Fixtures start script" and
# --slug fixtures-start-script are the same thing. A second task named the same
# as a live or archived one gets -2, then -3.
# The base branch comes from --base, else the project's data/projects.md line,
# else develop when the project has one, else the remote's default branch.
# --prefix is one word (a ticket number, say) naming this siding's DDEV
# project: the siding gets name <prefix>-<project> so it never clashes with
# another siding or your own checkout. It must match [A-Za-z0-9][A-Za-z0-9-]*
# and defaults to the task id, which is unique to this task. It falls back to
# that same default, saying so, when <prefix>-<project> will not fit a
# 63-character hostname label. It means nothing for a project without .ddev/.
# prints: id=<id>, base=<branch> and siding=<path>
set -euo pipefail
# shellcheck source=bin/ry-lib.sh
. "$(dirname "$0")/ry-lib.sh"
# shellcheck source=bin/ry-backend-lib.sh
. "$(dirname "$0")/ry-backend-lib.sh"

shape="" mode="" base="" after="" prefix="" prefix_set=0 project="" waybill=""
ticket="" slug=""
while [ $# -gt 0 ]; do
  case $1 in
    --haul)   shape=haul ;;
    --survey) shape=survey ;;
    --mode)   mode=${2:-}; shift ;;
    --base)   base=${2:-}; shift ;;
    --after)  after=${2:-}; shift ;;
    --prefix) prefix=${2:-}; prefix_set=1; shift ;;
    --ticket) ticket=${2:-}; shift ;;
    --slug)   slug=${2:-}; shift ;;
    -h|--help) ry_usage "$0"; exit 0 ;;
    --*)      ry_die "unknown flag $1" ;;
    *) if [ -z "$project" ]; then project=$1; else waybill=$1; fi ;;
  esac
  shift
done

[ -n "$shape" ]   || ry_die "need --haul or --survey"
[ -n "$project" ] || ry_die "need <project>"
[ -n "$waybill" ] || ry_die "need <waybill>"
# The waybill's first line is the task's title: bin/ry-pr.sh uses it verbatim
# as the PR/MR title. Checked here, before any state is written or any siding
# is cut, because this is the only moment it is cheap to fix -- the alternative
# is a rejected PR an hour later, with the branch already pushed.
wb_title=$(ry_first_line "$waybill")
[ ${#wb_title} -le $RY_TITLE_MAX ] || ry_die \
  "the waybill's first line is the task's title and must be at most $RY_TITLE_MAX characters; this one is ${#wb_title}. Put a short imperative summary of the whole task on line 1, leave line 2 blank, and start the body on line 3. Line 1 was: $wb_title"
# Validate before anything is written: a bad prefix would only surface as a
# DDEV project that refuses to start, long after dispatch.
[ "$prefix_set" -eq 0 ] || ry_prefix_valid "$prefix" \
  || ry_die "bad --prefix '$prefix': one token matching ^[A-Za-z0-9][A-Za-z0-9-]*$ (a ticket number or one short word)"
ticket=${ticket#\#}
[ -z "$ticket" ] || [[ $ticket =~ ^[0-9]+$ ]] \
  || ry_die "bad --ticket '$ticket': an issue or pull/merge request number, digits only"
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

# Name the task the way the dispatcher thinks about it, not the way railyard
# stores it: the ticket if there is one, and a slug of what the work is.
[ -n "$ticket" ] || ticket=$(ry_ticket_ref "$waybill")
[ -n "$slug" ] || slug=$waybill
slug=$(ry_slugify "$slug")
id=$(ry_new_id "$ticket" "$slug")
# No prefix given: the id itself, which is unique to this task.
[ -n "$prefix" ] || prefix=$(ry_ddev_default_prefix "$id" "$project")
# Too long for a DDEV project name: fall back to that same default rather
# than truncating, which would map two long prefixes onto one name. Dispatch is
# the only place this is decided, so the prefix= recorded below is always the
# one the siding's DDEV project is actually called. Said out loud, because a
# silent substitution leaves you hunting for a project that was never created.
if ! ry_ddev_name "$prefix" "$project" >/dev/null; then
  printf 'note: --prefix %s is too long for a DDEV project name (%s) -- using %s instead\n' \
    "$prefix" "$(ry_ddev_name_too_long "$prefix" "$project")" "$(ry_ddev_default_prefix "$id" "$project")"
  prefix=$(ry_ddev_default_prefix "$id" "$project")
fi
siding="$home/yard/$project/$id"
branch="ry/$id"

mkdir -p "$home/state"
cat > "$home/state/$id.meta" <<META
id=$id
project=$project
ticket=$ticket
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
  # Dispatch is all-or-nothing, but only for the failure this is actually
  # about: a launch that never opened a terminal. ry-couple.sh can also fail
  # for reasons that leave the task perfectly recoverable as `queued` (a
  # fetch failure, a diverged base, a bad --prefix) -- those already say so
  # on stderr, and rolling them back too would blame "the backend" for a
  # cause this script cannot see and cannot know. The sentinel ry-couple.sh
  # writes only on a launch failure (see there, and ry-watch.sh) is the
  # signal: present, this task never existed as far as anyone but this
  # script is concerned, so every trace this script itself wrote gets
  # undone -- ry-couple.sh has already rolled the siding, branch and status
  # back by the time it fails, so there is nothing left to relaunch, only to
  # redo. Absent, the id=/base=/siding= lines above already say enough; the
  # error ry-couple.sh printed explains why, and the task is left queued.
  if ! "$(dirname "$0")/ry-couple.sh" "$id" >/dev/null; then
    if [ -e "$home/state/$id.launch-failed" ]; then
      rm -f "$home/state/$id.meta" "$home/state/$id.status" "$home/state/$id.waybill.md" \
            "$home/state/$id.settings.json" "$home/state/$id.setup-failed.md" \
            "$home/state/$id.start.log" "$home/state/$id.launch-failed"
      rm -rf "$home/data/$id"
      printf 'FAILED: dispatch of %s could not launch an engine; everything written for it has been rolled back. Fix the backend and dispatch again -- there is nothing to recover, this attempt left no trace.\n' "$id" >&2
    else
      printf 'FAILED: dispatch of %s could not be coupled; see the error above. %s is left queued so nothing is lost -- fix it and run bin/ry-couple.sh %s to retry.\n' "$id" "$id" "$id" >&2
    fi
    exit 1
  fi
fi
