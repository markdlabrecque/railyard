#!/usr/bin/env bash
# Arm auto-merge on an already-open PR/MR whose task opted in via ry-pr.sh
# --auto-merge (auto_merge=<method> in state/<id>.meta). Run by the watcher on
# the same cadence as the PR poll, for every pr-mode task with auto_merge set.
#
# Auto-merge on both forges fires against "nothing pending", not "checks
# passed": a head commit with no check created yet merges unreviewed the
# instant it is armed, seconds before CI or CodeRabbit ever starts. So this
# script is the gate: it reads the forge's own view of the PR head -- never
# the local worktree HEAD -- and refuses to arm anything until at least one
# check has been created for that exact commit. Arming writes the gated sha to
# state/<id>.auto-armed; the merge itself is left to the forge, and observed
# back by ry-pr-poll.sh so queued tasks still couple on pr-merged (#10).
#
# Being armed is not the end of it. GitHub keeps auto-merge enabled across a
# later push, so an armed PR whose head has moved is disarmed and re-gated
# from scratch — otherwise the gate would hold only for the commit that
# happened to be at the head when it was armed.
#
# usage: ry-auto-merge.sh <id>
set -euo pipefail
# shellcheck source=bin/ry-lib.sh
. "$(dirname "$0")/ry-lib.sh"
# shellcheck source=bin/ry-forge-lib.sh
. "$(dirname "$0")/ry-forge-lib.sh"
case ${1:-} in -h|--help) ry_usage "$0"; exit 0 ;; esac

id=${1:-}
[ -n "$id" ] || ry_die "need <id>"

home=$(ry_home); st="$home/state"
url=$(ry_meta_get "$id" pr_url)
auto_merge=$(ry_meta_get "$id" auto_merge)
[ -n "$url" ] || ry_die "no PR recorded for $id"
[ -n "$auto_merge" ] || ry_die "auto-merge is not enabled for $id (no auto_merge= in its meta)"

# The armed sha, if this task has already been armed once. Being armed is not
# the end of the story: GitHub keeps auto-merge enabled across a later push,
# so an armed PR whose head has moved is disarmed and re-gated from scratch,
# rather than merging a commit no check was ever created for.
armed=$(cat "$st/$id.auto-armed" 2>/dev/null || true)

forge=$(ry_meta_get "$id" forge); siding=$(ry_meta_get "$id" siding)
case $forge in
  github) ry_require gh jq ;;
  gitlab) ry_require glab jq ;;
  *) ry_die "unknown forge '$forge'" ;;
esac

tries=${RY_AUTO_MERGE_TRIES:-10}
sleep_s=${RY_AUTO_MERGE_SLEEP:-3}

event() { printf '%s %s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$id" "$*" >> "$st/events.log"; }

arm() {  # <sha>: write auto-armed, log the event, print, and exit clean
  printf '%s\n' "$1" > "$st/$id.auto-armed"
  event "auto-merge-armed $url sha=$1"
  printf 'auto-merge=armed sha=%s\n' "$1"
  exit 0
}

# Every non-arming outcome is logged through one guard, because the watcher
# calls this script once per PR poll for as long as the task is unarmed. An
# unguarded event would post an inbox line per poll — forever, for a PR that
# conflicts, or on a repo where auto-merge is simply switched off. The guard
# remembers "<kind> <reason> <sha>", so the same situation on the same head
# says nothing twice, and a new head says it again.
notice() {  # <kind> <reason> [<sha>]
  local seen key="$1 $2 ${3:-}"
  seen=$(cat "$st/$id.auto-notice" 2>/dev/null || true)
  [ "$seen" = "$key" ] && return 0
  printf '%s\n' "$key" > "$st/$id.auto-notice"
  event "auto-merge-$1 $url reason=$2"
}

waiting_no_checks() {  # <sha>
  notice waiting no-checks "$1"
  printf 'auto-merge=waiting reason=no-checks\n'
  exit 0
}

waiting_checking() {  # <sha>: the 405/checking retry budget ran out; a later pass retries
  notice waiting checking "$1"
  printf 'auto-merge=waiting reason=checking\n'
  exit 0
}

blocked() {  # <reason> <sha>
  notice blocked "$1" "$2"
  printf 'auto-merge=blocked reason=%s\n' "$1"
  exit 0
}

skipped() {  # <state>: PR/MR already merged or closed elsewhere
  printf 'auto-merge=skipped reason=%s\n' "$1"
  exit 0
}

unavailable() {  # <short> <sha>: a merge failure that is not 405/checking
  notice blocked unavailable "$2"
  printf 'auto-merge=unavailable reason=%s\n' "$1"
  exit 0
}

disarmed() {  # <sha>: the head moved off the armed commit
  rm -f "$st/$id.auto-armed" "$st/$id.auto-notice"
  event "auto-merge-disarmed $url sha=$1"
  printf 'auto-merge=disarmed sha=%s\n' "$1"
  exit 0
}

case $forge in
  github)
    json=$(cd "$siding" && gh pr view "$url" --json state,headRefOid,mergeStateStatus,statusCheckRollup)
    state=$(jq -r '.state | ascii_downcase' <<<"$json")
    case $state in open) ;; *) skipped "$state" ;; esac
    sha=$(jq -r '.headRefOid' <<<"$json")
    if [ -n "$armed" ]; then
      [ "$armed" != "$sha" ] || { printf 'auto-merge=armed sha=%s\n' "$sha"; exit 0; }
      # Only claim a disarm that actually happened: saying auto-merge is off
      # while GitHub still has it on, for a head no check was created for, is
      # the one lie that could merge the very commit this gate exists to hold.
      out=$(cd "$siding" && gh pr merge "$url" --disable-auto 2>&1) && rc=0 || rc=$?
      if [ "$rc" -ne 0 ]; then
        case $out in
          *"not enabled"*|*"not have auto-merge"*|*"Auto merge is not"*) ;;
          *) notice blocked disarm-failed "$sha"
             printf 'auto-merge=blocked reason=disarm-failed\n'; exit 0 ;;
        esac
      fi
      disarmed "$sha"
    fi

    # Only a check that can actually report a verdict counts as a check having
    # been created. A path-filtered workflow answers "skipped" within seconds
    # of the push, long before CI or a reviewer has posted anything: counting
    # that as a check would arm — and, being "all green", merge at once — the
    # very commit nothing has looked at.
    count=$(jq -r '[.statusCheckRollup[]?
      | (.conclusion // .state // .status // "") | ascii_downcase
      | select(. != "skipped" and . != "neutral")] | length' <<<"$json")
    [ "$count" -gt 0 ] || waiting_no_checks "$sha"

    merge=$(jq -r '(.mergeStateStatus // "") | ascii_downcase' <<<"$json")
    [ "$merge" != dirty ] || blocked conflict "$sha"

    # shellcheck disable=SC2016  # jq program: $c is a jq variable, not shell
    checks=$(jq -r '
      [.statusCheckRollup[]? | (.conclusion // .state // .status // "") | ascii_downcase] as $c
      | if any($c[]; . == "failure" or . == "error" or . == "cancelled" or . == "timed_out" or . == "action_required") then "failure"
        elif all($c[]; . == "success" or . == "neutral" or . == "skipped") then "success"
        else "pending" end' <<<"$json")
    [ "$checks" != failure ] || blocked checks-failed "$sha"

    # Always pin the head commit, so a push landing between the gate and the
    # merge cannot slip through unchecked. --auto is only safe here because
    # the gate above already proved a check exists for this exact sha.
    args=(pr merge "$url")
    [ "$checks" = pending ] && args+=(--auto)
    args+=(--"$auto_merge" --match-head-commit "$sha")
    out=$(cd "$siding" && gh "${args[@]}" 2>&1) && rc=0 || rc=$?
    [ "$rc" -eq 0 ] && arm "$sha"
    unavailable "$(printf '%s\n' "$out" | head -n1)" "$sha"
    ;;
  gitlab)
    n=$(ry_pr_number "$url")
    fetch() { cd "$siding" && glab api "projects/:id/merge_requests/$n"; }
    settle_status() { jq -r '(.detailed_merge_status // "") | ascii_downcase' <<<"$1"; }

    json=$(fetch)
    ds=$(settle_status "$json")
    i=1
    # GitLab answers 405 while it is still working out mergeability, not just
    # on the merge call itself; settle first so the gate below reads a real
    # verdict instead of "checking".
    while case $ds in checking | unchecked | cannot_be_merged_recheck) true ;; *) false ;; esac \
          && [ "$i" -lt "$tries" ]; do
      sleep "$sleep_s"
      json=$(fetch)
      ds=$(settle_status "$json")
      i=$((i + 1))
    done

    state=$(jq -r '.state' <<<"$json")
    case $state in opened) ;; *) skipped "$state" ;; esac

    mr_sha=$(jq -r '.sha' <<<"$json")
    if [ -n "$armed" ]; then
      # A push resets merge-when-pipeline-succeeds on GitLab by itself, so
      # there is nothing to disable — only to notice and re-gate.
      [ "$armed" != "$mr_sha" ] || { printf 'auto-merge=armed sha=%s\n' "$mr_sha"; exit 0; }
      disarmed "$mr_sha"
    fi

    pstatus=$(jq -r '(.head_pipeline.status // "") | ascii_downcase' <<<"$json")
    pipeline_sha=$(jq -r '.head_pipeline.sha // ""' <<<"$json")
    # A pipeline for an older sha is not a check on this head; and "skipped" or
    # "manual" is a pipeline that will never report, which GitLab's auto-merge
    # reads as nothing pending.
    { [ -n "$pipeline_sha" ] && [ "$pipeline_sha" = "$mr_sha" ] &&
      [ "$pstatus" != skipped ] && [ "$pstatus" != manual ]; } || waiting_no_checks "$mr_sha"

    merge=$(jq -r '(.detailed_merge_status // "") | ascii_downcase
      | if   . == "mergeable" or . == "can_be_merged" then "clean"
        elif . == "conflict" or . == "broken_status" or . == "cannot_be_merged" then "dirty"
        else "other" end' <<<"$json")
    [ "$merge" != dirty ] || blocked conflict "$mr_sha"

    case $pstatus in failed | canceled) blocked checks-failed "$mr_sha" ;; esac

    # --yes is mandatory on every glab merge call: without it glab prompts for
    # confirmation, which is the same trap `ddev delete` fell into once.
    args=(mr merge "$n" --yes)
    [ "$pstatus" = success ] || args+=(--auto-merge)
    args+=(--sha "$mr_sha")
    case $auto_merge in squash) args+=(--squash) ;; rebase) args+=(--rebase) ;; esac

    attempt=1
    while :; do
      out=$(cd "$siding" && glab "${args[@]}" 2>&1) && rc=0 || rc=$?
      [ "$rc" -eq 0 ] && arm "$mr_sha"
      # Matched narrowly: a bare *405* also matches MR !405, a sha fragment or
      # a byte count, and would turn a real failure into a silent retry.
      case $out in *"Method Not Allowed"* | *": 405"* | *"405:"*)
        [ "$attempt" -lt "$tries" ] || waiting_checking "$mr_sha"
        attempt=$((attempt + 1))
        sleep "$sleep_s"
        continue ;;
      esac
      unavailable "$(printf '%s\n' "$out" | head -n1)" "$mr_sha"
    done
    ;;
esac
