#!/usr/bin/env bash
# Watcher daemon. Zero tokens: pure bash polling state/ every RY_WATCH_INTERVAL
# seconds (default 2). Each pass:
#   1. new lines in state/events.log -> one inbox line each, injected into the
#      yardmaster's tmux pane (state/yardmaster.pane) when it exists;
#   2. engines with status "running" untouched for RY_STALL_MIN minutes
#      (default 20) -> one "silent" inbox line, once per engine.
# The inbox (state/inbox.md) is the durable record; pane injection is a nudge.
# usage: ry-watch.sh [--once]
set -uo pipefail
# shellcheck source=bin/ry-lib.sh
. "$(dirname "$0")/ry-lib.sh"
# shellcheck source=bin/ry-tmux-lib.sh
. "$(dirname "$0")/ry-tmux-lib.sh"

home=$(ry_home); st="$home/state"
inbox="$st/inbox.md"; events="$st/events.log"; cursor="$st/.watch.cursor"
stall_min=${RY_STALL_MIN:-20}
interval=${RY_WATCH_INTERVAL:-2}

post() {  # <line>: durable first, nudge second
  printf '%s\n' "$1" >> "$inbox"
  local pane
  pane=$(cat "$st/yardmaster.pane" 2>/dev/null || true)
  [ -n "$pane" ] || return 0
  if ry_tmux display -p -t "$pane" '#{pane_id}' >/dev/null 2>&1; then
    ry_tmux send-keys -t "$pane" -l -- "$1" && ry_tmux send-keys -t "$pane" Enter
  fi
}

pass() {
  # 1. events
  local seen=0 total=0
  seen=$(cat "$cursor" 2>/dev/null || echo 0)
  if [ -f "$events" ]; then
    total=$(grep -c . "$events" || true)
    if [ "$total" -gt "$seen" ]; then
      tail -n +"$((seen + 1))" "$events" | while read -r _ts id kind; do
        [ -n "$id" ] || continue
        local last=""
        [ -f "$st/$id.last.md" ] && last=$(head -n1 "$st/$id.last.md")
        post "[railyard] engine $id $kind: $last"
      done
      printf '%s\n' "$total" > "$cursor"
    fi
  fi
  # 2. stalls
  local f id age now
  now=$(date +%s)
  for f in "$st"/*.status; do
    [ -f "$f" ] || continue
    [ "$(cat "$f")" = running ] || continue
    id=${f##*/}; id=${id%.status}
    [ -e "$st/$id.stall-warned" ] && continue
    age=$(( (now - $(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f")) / 60 ))
    if [ "$age" -ge "$stall_min" ]; then
      post "[railyard] engine $id silent for ${age}m (status running, no turn end); check window ry-$id"
      : > "$st/$id.stall-warned"
    fi
  done
}

if [ "${1:-}" = --once ]; then pass; exit 0; fi

lock="$st/.watch.lock"
if pid=$(cat "$lock" 2>/dev/null) && [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && [ "$pid" != "$$" ]; then
  exit 0  # another watcher is alive
fi
printf '%s\n' "$$" > "$lock"
trap 'rm -f "$lock"' EXIT
while :; do pass; sleep "$interval"; done
