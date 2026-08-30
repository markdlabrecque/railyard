#!/usr/bin/env bash
# Claude Stop hook for engines. Reads the hook JSON on stdin, marks the engine
# turn-ended, appends to state/events.log, and saves the last assistant text
# (the whole final message; its first line is the DONE:/BLOCKED: handoff)
# to state/<id>.last.md for the yardmaster's wake message.
# Always exits 0: an engine must never be blocked by its own reporter.
set -u
# shellcheck source=bin/ry-lib.sh
. "$(dirname "$0")/ry-lib.sh"

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
