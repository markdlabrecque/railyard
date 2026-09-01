#!/usr/bin/env bash
# Claude Stop hook for engines. Reads the hook JSON on stdin, marks the engine
# turn-ended, appends to state/events.log, and saves the last assistant text
# (the whole final message; its first line is the DONE:/BLOCKED: handoff)
# to state/<id>.last.md for the yardmaster's wake message.
#
# Since issue #5 the hook is registered in two places (the argv --settings file
# and the siding's own .claude/settings.local.json) so that a --resume relaunch
# cannot lose it. That is not two reports: Claude Code fires an identical hook
# command once however many settings sources name it. This script therefore
# does no de-duplication of its own -- deliberately. Anything that decided a
# turn end was a duplicate would be the one thing this script must never do,
# swallow one, and that is the whole of issue #5.
#
# Always exits 0: an engine must never be blocked by its own reporter.
# usage: Claude Stop hook for an engine session; hook JSON on stdin, RY_ID set.
set -u
# shellcheck source=bin/ry-lib.sh
. "$(dirname "$0")/ry-lib.sh"
case ${1:-} in -h|--help) ry_usage "$0"; exit 0 ;; esac

input=$(cat || true)
id=${RY_ID:-}
[ -n "$id" ] || exit 0
home=$(ry_home)
[ -f "$home/state/$id.meta" ] || exit 0

active=$(jq -r '.stop_hook_active // false' <<<"$input" 2>/dev/null || echo false)
[ "$active" = "true" ] && exit 0

transcript=$(jq -r '.transcript_path // empty' <<<"$input" 2>/dev/null || true)
if [ -n "$transcript" ] && [ -f "$transcript" ]; then
  jq -rs '[.[] | select(.type=="assistant") | .message.content[]? | select(.type=="text") | .text] | last // empty' \
    "$transcript" > "$home/state/$id.last.md" 2>/dev/null || true
fi

ry_set_status "$id" turn-ended
printf '%s %s turn-ended\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$id" >> "$home/state/events.log"
exit 0
