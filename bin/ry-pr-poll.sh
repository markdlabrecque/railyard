#!/usr/bin/env bash
# Check an open PR/MR once and say what changed. Prints one line:
#   state=<open|merged|closed> checks=<success|failure|pending|none>
#   merge=<clean|dirty|blocked|unknown> findings=<n|n/a|-> [worst=<sev>]
#
# At most one event per poll, and only when the situation actually changes.
# The last reported situation lives in state/<id>.pr-phase, so a PR that goes
# green, gets a push, goes red and goes green again reports twice — once per
# real transition — while a PR that just sits there green reports once.
#
#   pr-merged <url>                     merged (status -> merged)
#   pr-ready <url> checks=N findings=N  open, mergeable, every check green
#   pr-no-checks <url> findings=N       open, mergeable, and no check ran at all
#   pr-conflict <url>                   open, conflicts with its base branch
#   pr-checks-failed <url>              open, a check failed
#
# "unknown" mergeability is GitHub recomputing after a push. It is not ready,
# but it is not a situation either: the phase file is left untouched, so the
# event still fires when the real answer arrives a minute later.
#
# Findings are unresolved reviewer threads, counted through GitHub's GraphQL
# reviewThreads: a thread that is resolved or outdated is not a finding, nor is
# one CodeRabbit has marked "Addressed in commits X to Y" without deleting.
# Only the count and the worst severity travel; the bodies stay on the forge.
# GitLab reports findings=n/a: reviewer notes there carry no severity and no
# resolution CodeRabbit-style, so a number would be invented rather than read.
# usage: ry-pr-poll.sh <id>
set -euo pipefail
# shellcheck source=bin/ry-lib.sh
. "$(dirname "$0")/ry-lib.sh"
# shellcheck source=bin/ry-forge-lib.sh
. "$(dirname "$0")/ry-forge-lib.sh"
case ${1:-} in -h|--help) ry_usage "$0"; exit 0 ;; esac

id=${1:-}; [ -n "$id" ] || ry_die "need <id>"
home=$(ry_home); st="$home/state"
url=$(ry_meta_get "$id" pr_url); forge=$(ry_meta_get "$id" forge); siding=$(ry_meta_get "$id" siding)
[ -n "$url" ] || ry_die "no PR recorded for $id"
case $forge in github) ry_require gh jq ;; gitlab) ry_require glab jq ;; esac

event() { printf '%s %s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$id" "$*" >> "$st/events.log"; }

# Unresolved reviewer findings on a GitHub PR -> "<count> <worst-severity>".
# shellcheck disable=SC2016  # jq program: $s and $n are jq variables, not shell
findings_jq='
[ .data.repository.pullRequest.reviewThreads.nodes[]?
  | select((.isResolved // false) | not)
  | select((.isOutdated // false) | not)
  | (.comments.nodes[0].body // "")
  | select(test("addressed in commit"; "i") | not)
  | (split("\n")[0] | ascii_downcase)
  | if   test("critical") then 4 elif test("major")   then 3
    elif test("minor")    then 2 elif test("nitpick") then 1 else 0 end
] as $s
| ($s | length) as $n
| "\($n) " + (if $n == 0 then "none" else
    ($s | max) as $m
    | if   $m == 4 then "critical" elif $m == 3 then "major"
      elif $m == 2 then "minor"    elif $m == 1 then "nitpick"
      else "unlabelled" end end)'

gh_findings() {  # -> "<count> <worst>", or "unknown unknown" if the query fails
  local q owner repo num out
  owner=$(sed -E 's#^https?://[^/]+/([^/]+)/([^/]+)/pull/[0-9]+/?$#\1#' <<<"$url")
  repo=$(sed -E 's#^https?://[^/]+/([^/]+)/([^/]+)/pull/[0-9]+/?$#\2#' <<<"$url")
  num=$(ry_pr_number "${url%/}")
  # shellcheck disable=SC2016  # GraphQL variables
  q='query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){pullRequest(number:$n){
       reviewThreads(first:100){nodes{isResolved isOutdated comments(first:1){nodes{body}}}}}}}'
  out=$(cd "$siding" && gh api graphql -f query="$q" -F o="$owner" -F r="$repo" -F n="$num" 2>/dev/null) || {
    printf 'unknown unknown\n'; return; }
  jq -r "$findings_jq" <<<"$out" 2>/dev/null || printf 'unknown unknown\n'
}

case $forge in
  github)
    json=$(cd "$siding" && gh pr view "$url" --json state,statusCheckRollup,mergeStateStatus)
    state=$(jq -r '.state | ascii_downcase' <<<"$json")
    checks=$(jq -r '
      [.statusCheckRollup[]? | (.conclusion // .state // .status // "") | ascii_downcase] as $c
      | if ($c|length)==0 then "none"
        elif any($c[]; . == "failure" or . == "error" or . == "cancelled" or . == "timed_out" or . == "action_required") then "failure"
        elif all($c[]; . == "success" or . == "neutral" or . == "skipped") then "success"
        else "pending" end' <<<"$json")
    check_count=$(jq -r '[.statusCheckRollup[]?] | length' <<<"$json")
    merge=$(jq -r '(.mergeStateStatus // "") | ascii_downcase
      | if   . == "clean" or . == "has_hooks" or . == "unstable" then "clean"
        elif . == "dirty" then "dirty"
        elif . == "" or . == "unknown" then "unknown"
        else "blocked" end' <<<"$json") ;;
  gitlab)
    json=$(cd "$siding" && glab mr view "$(ry_pr_number "$url")" -F json)
    state=$(jq -r '.state' <<<"$json"); [ "$state" = opened ] && state=open
    checks=$(jq -r '(.head_pipeline.status // .pipeline.status // "none") as $s
      | if $s == "none" then "none"
        elif $s == "success" then "success"
        elif ($s == "failed" or $s == "canceled") then "failure"
        else "pending" end' <<<"$json")
    check_count=$(jq -r 'if (.head_pipeline.status // .pipeline.status // null) == null then 0 else 1 end' <<<"$json")
    # detailed_merge_status is the modern field; merge_status is the old one.
    # "checking" is GitLab still working it out — the same transient as UNKNOWN,
    # and the reason `glab mr merge` answers 405 on a fresh MR.
    merge=$(jq -r '(.detailed_merge_status // .merge_status // "") | ascii_downcase
      | if   . == "mergeable" or . == "can_be_merged" then "clean"
        elif . == "conflict" or . == "broken_status" or . == "cannot_be_merged" then "dirty"
        elif . == "" or . == "checking" or . == "unchecked" or . == "cannot_be_merged_recheck" then "unknown"
        else "blocked" end' <<<"$json") ;;
  *) ry_die "unknown forge '$forge'" ;;
esac

# Which situation is this? Empty means "nothing to remember" (transient).
phase=""
case $state in
  merged) phase=merged ;;
  closed) phase=closed ;;
  *)
    if   [ "$checks" = failure ]; then phase="checks-failed"
    elif [ "$merge"  = dirty   ]; then phase=conflict
    elif [ "$merge"  = unknown ]; then phase=""
    elif [ "$checks" = pending ]; then phase=pending
    elif [ "$merge"  != clean  ]; then phase=blocked
    elif [ "$checks" = none    ]; then phase="no-checks"
    else phase=ready; fi ;;
esac

findings=- worst=""
if [ "$phase" = ready ] || [ "$phase" = no-checks ]; then
  case $forge in
    github) read -r findings worst <<<"$(gh_findings)" ;;
    gitlab) findings=n/a worst=n/a ;;
  esac
fi

last=$(cat "$st/$id.pr-phase" 2>/dev/null || true)
if [ -n "$phase" ] && [ "$phase" != "$last" ]; then
  printf '%s\n' "$phase" > "$st/$id.pr-phase"
  case $phase in
    merged)
      if [ "$(cat "$st/$id.status")" != merged ]; then
        ry_set_status "$id" merged; event "pr-merged $url"
      fi ;;
    ready)         event "pr-ready $url checks=$check_count findings=$findings worst=$worst" ;;
    no-checks)     event "pr-no-checks $url findings=$findings worst=$worst" ;;
    conflict)      event "pr-conflict $url" ;;
    checks-failed) event "pr-checks-failed $url" ;;
  esac
fi

printf 'state=%s checks=%s merge=%s findings=%s\n' "$state" "$checks" "$merge" "$findings"
