#!/usr/bin/env bash
# Arm auto-merge on an already-open PR/MR whose task opted in via ry-pr.sh
# --auto-merge (auto_merge=<method> in state/<id>.meta). Run by the watcher,
# once per pass, for every unarmed pr-mode task with auto_merge set.
#
# Auto-merge on both forges fires against "nothing pending", not "checks
# passed": a head commit with no check created yet merges unreviewed the
# instant it is armed, seconds before CI or CodeRabbit ever starts. So this
# script is the gate: it reads the forge's own view of the PR head -- never
# the local worktree HEAD -- and refuses to arm anything until at least one
# check has been created for that exact commit. Armed once, it writes
# state/<id>.auto-armed and never calls the forge again for this task; the
# merge itself is left to the forge, and observed back by ry-pr-poll.sh so
# queued tasks still couple on pr-merged (#10).
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

# Already armed: nothing to do, and no forge call at all.
[ ! -e "$st/$id.auto-armed" ] || exit 0

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

waiting_no_checks() {
  # Guarded so repeated watcher passes over an unchanged, check-less head do
  # not spam the inbox with the same "still waiting" line.
  if [ ! -e "$st/$id.auto-waited" ]; then
    : > "$st/$id.auto-waited"
    event "auto-merge-waiting $url reason=no-checks"
  fi
  printf 'auto-merge=waiting reason=no-checks\n'
  exit 0
}

waiting_checking() {  # the 405/checking retry budget ran out; a later pass tries again
  printf 'auto-merge=waiting reason=checking\n'
  exit 0
}

blocked() {  # <reason>
  event "auto-merge-blocked $url reason=$1"
  printf 'auto-merge=blocked reason=%s\n' "$1"
  exit 0
}

skipped() {  # <state>: PR/MR already merged or closed elsewhere
  printf 'auto-merge=skipped reason=%s\n' "$1"
  exit 0
}

unavailable() {  # <short>: a merge failure that is not 405/checking
  event "auto-merge-blocked $url reason=unavailable"
  printf 'auto-merge=unavailable reason=%s\n' "$1"
  exit 0
}

case $forge in
  github)
    json=$(cd "$siding" && gh pr view "$url" --json state,headRefOid,mergeStateStatus,statusCheckRollup)
    state=$(jq -r '.state | ascii_downcase' <<<"$json")
    case $state in open) ;; *) skipped "$state" ;; esac
    sha=$(jq -r '.headRefOid' <<<"$json")

    count=$(jq -r '[.statusCheckRollup[]?] | length' <<<"$json")
    [ "$count" -gt 0 ] || waiting_no_checks

    merge=$(jq -r '(.mergeStateStatus // "") | ascii_downcase' <<<"$json")
    [ "$merge" != dirty ] || blocked conflict

    # shellcheck disable=SC2016  # jq program: $c is a jq variable, not shell
    checks=$(jq -r '
      [.statusCheckRollup[]? | (.conclusion // .state // .status // "") | ascii_downcase] as $c
      | if any($c[]; . == "failure" or . == "error" or . == "cancelled" or . == "timed_out" or . == "action_required") then "failure"
        elif all($c[]; . == "success" or . == "neutral" or . == "skipped") then "success"
        else "pending" end' <<<"$json")
    [ "$checks" != failure ] || blocked checks-failed

    # Always pin the head commit, so a push landing between the gate and the
    # merge cannot slip through unchecked. --auto is only safe here because
    # the gate above already proved a check exists for this exact sha.
    args=(pr merge "$url")
    [ "$checks" = pending ] && args+=(--auto)
    args+=(--"$auto_merge" --match-head-commit "$sha")
    out=$(cd "$siding" && gh "${args[@]}" 2>&1) && rc=0 || rc=$?
    [ "$rc" -eq 0 ] && arm "$sha"
    unavailable "$(printf '%s\n' "$out" | head -n1)"
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
    pipeline_sha=$(jq -r '.head_pipeline.sha // ""' <<<"$json")
    [ -n "$pipeline_sha" ] && [ "$pipeline_sha" = "$mr_sha" ] || waiting_no_checks

    merge=$(jq -r '(.detailed_merge_status // "") | ascii_downcase
      | if   . == "mergeable" or . == "can_be_merged" then "clean"
        elif . == "conflict" or . == "broken_status" or . == "cannot_be_merged" then "dirty"
        else "other" end' <<<"$json")
    [ "$merge" != dirty ] || blocked conflict

    pstatus=$(jq -r '(.head_pipeline.status // "") | ascii_downcase' <<<"$json")
    case $pstatus in failed | canceled) blocked checks-failed ;; esac

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
      case $out in *405* | *"Method Not Allowed"*)
        [ "$attempt" -lt "$tries" ] || waiting_checking
        attempt=$((attempt + 1))
        sleep "$sleep_s"
        continue ;;
      esac
      unavailable "$(printf '%s\n' "$out" | head -n1)"
    done
    ;;
esac
