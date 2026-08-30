#!/usr/bin/env bash
# Yardmaster SessionStart hook: remember which tmux pane the yardmaster is in
# (for wake nudges), make sure one watcher daemon is running, and print a short
# yard summary that lands in the session context.
set -uo pipefail
# shellcheck source=bin/ry-lib.sh
. "$(dirname "$0")/ry-lib.sh"
home=$(ry_home); st="$home/state"; bindir=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$st"
cat >/dev/null || true   # drain hook stdin

if [ -n "${TMUX_PANE:-}" ]; then printf '%s\n' "$TMUX_PANE" > "$st/yardmaster.pane"; fi

lock="$st/.watch.lock"
if ! { pid=$(cat "$lock" 2>/dev/null) && [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; }; then
  RY_HOME=$home nohup "$bindir/ry-watch.sh" >>"$st/watch.log" 2>&1 </dev/null &
  disown 2>/dev/null || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$lock" ] && break; sleep 0.1; done
fi

running=0 ended=0
for f in "$st"/*.status; do
  [ -f "$f" ] || continue
  case $(cat "$f") in running) running=$((running+1));; turn-ended) ended=$((ended+1));; esac
done
unread=0; [ -s "$st/inbox.md" ] && unread=$(grep -c . "$st/inbox.md")
printf 'railyard: %d engine(s) running, %d turn-ended, %d unread inbox line(s). Read with bin/ry-inbox.sh.\n' "$running" "$ended" "$unread"
