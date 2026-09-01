#!/usr/bin/env bash
# Claude Stop hook for engines. Reads the hook JSON on stdin, marks the engine
# turn-ended, appends to state/events.log, and saves the last assistant text
# (the whole final message; its first line is the DONE:/BLOCKED: handoff)
# to state/<id>.last.md for the yardmaster's wake message.
#
# Registered twice since issue #5 (argv --settings, and the siding's own
# settings.local.json), so one real turn end can invoke this script twice.
# Deduped on session_id + the transcript's size and line count, kept in
# state/<id>.turnend.key: an identical key is a duplicate invocation of the
# same turn and is a silent no-op. Anything that cannot be keyed (no
# session_id, or the transcript missing/unreadable) always reports -- a
# swallowed real turn end is far worse than one duplicate report.
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

# Dedupe key: session_id plus the transcript's current size and line count, so
# a grown transcript under the same session (a later turn) still keys fresh.
# No session_id, or a transcript that cannot be sized, means no key at all --
# and no key means always report, never cache a decision on data this thin.
session_id=$(jq -r '.session_id // empty' <<<"$input" 2>/dev/null || true)
key=""
if [ -n "$session_id" ] && [ -n "$transcript" ] && [ -f "$transcript" ] && [ -r "$transcript" ]; then
  size=$(wc -c < "$transcript" 2>/dev/null | tr -d ' ' || true)
  lines=$(wc -l < "$transcript" 2>/dev/null | tr -d ' ' || true)
  if [ -n "$size" ] && [ -n "$lines" ]; then
    key="$session_id:$size:$lines"
  fi
fi
keyfile="$home/state/$id.turnend.key"
if [ -n "$key" ]; then
  last_key=$(cat "$keyfile" 2>/dev/null || true)
  [ "$key" = "$last_key" ] && exit 0
  printf '%s' "$key" > "$keyfile" 2>/dev/null || true
fi

ry_set_status "$id" turn-ended
printf '%s %s turn-ended\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$id" >> "$home/state/events.log"
exit 0
