#!/usr/bin/env bash
# Check an open PR/MR once. Prints "state=<open|merged|closed> checks=<pending|success|failure|none>".
# On merged: status -> merged, event "pr-merged <url>". On failing checks:
# event "pr-checks-failed <url>" once (marker state/<id>.checks-failed).
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

event() { printf '%s %s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$id" "$*" >> "$st/events.log"; }

case $forge in
  github)
    json=$(cd "$siding" && gh pr view "$url" --json state,statusCheckRollup)
    state=$(jq -r '.state | ascii_downcase' <<<"$json")
    checks=$(jq -r '
      [.statusCheckRollup[]? | (.conclusion // .state // .status // "") | ascii_downcase] as $c
      | if ($c|length)==0 then "none"
        elif any($c[]; . == "failure" or . == "error" or . == "cancelled" or . == "timed_out" or . == "action_required") then "failure"
        elif all($c[]; . == "success" or . == "neutral" or . == "skipped") then "success"
        else "pending" end' <<<"$json") ;;
  gitlab)
    json=$(cd "$siding" && glab mr view "$(ry_pr_number "$url")" -F json)
    state=$(jq -r '.state' <<<"$json"); [ "$state" = opened ] && state=open
    checks=$(jq -r '(.head_pipeline.status // .pipeline.status // "none") as $s
      | if $s == "none" then "none"
        elif $s == "success" then "success"
        elif ($s == "failed" or $s == "canceled") then "failure"
        else "pending" end' <<<"$json") ;;
  *) ry_die "unknown forge '$forge'" ;;
esac

if [ "$state" = merged ] && [ "$(cat "$st/$id.status")" != merged ]; then
  ry_set_status "$id" merged; event "pr-merged $url"
elif [ "$checks" = failure ] && [ ! -e "$st/$id.checks-failed" ]; then
  : > "$st/$id.checks-failed"; event "pr-checks-failed $url"
fi
printf 'state=%s checks=%s\n' "$state" "$checks"
