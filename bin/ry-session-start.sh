#!/usr/bin/env bash
# Yardmaster SessionStart hook: claim the yard for this session, make sure one
# watcher daemon is running, and print a short yard summary that lands in the
# session context.
#
# One session holds the yard at a time. The claim is the terminal the watcher
# nudges to wake it — a tmux pane or an Orca handle, whichever the backend
# uses. A session that starts while another live terminal holds the yard is
# told so rather than silently stealing it: two yardmasters share one inbox and
# take work from each other.
# usage: Claude SessionStart hook, run from the railyard home.
set -uo pipefail
# shellcheck source=bin/ry-lib.sh
. "$(dirname "$0")/ry-lib.sh"
# shellcheck source=bin/ry-backend-lib.sh
. "$(dirname "$0")/ry-backend-lib.sh"
case ${1:-} in -h|--help) ry_usage "$0"; exit 0 ;; esac
home=$(ry_home); st="$home/state"; bindir=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$st"
cat >/dev/null || true   # drain hook stdin

claim=$(ry_backend_claim_file); self=$(ry_backend_self)
held=$(cat "$claim" 2>/dev/null || true)
if [ -n "$held" ] && ! ry_backend_alive "$held"; then
  held=""   # the terminal that held the yard is gone
fi

if [ -n "$self" ] && { [ -z "$held" ] || [ "$held" = "$self" ]; }; then
  printf '%s\n' "$self" > "$claim"
  standing="you are the yardmaster."
elif [ -n "$held" ]; then
  standing="another yardmaster holds the yard ($held). Do not dispatch or act on the inbox — you would take work from it. Ask the dispatcher before taking over."
else
  standing="you are the yardmaster, but no terminal holds the yard, so the watcher cannot wake you. Check bin/ry-manifest.sh yourself instead of ending your turn to wait."
fi

lock="$st/.watch.lock"
if ! { pid=$(cat "$lock" 2>/dev/null) && [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; }; then
  RY_HOME=$home nohup "$bindir/ry-watch.sh" >>"$st/watch.log" 2>&1 </dev/null 3>&- &
  disown 2>/dev/null || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$lock" ] && break; sleep 0.1; done
fi

running=0 ended=0
for f in "$st"/*.status; do
  [ -f "$f" ] || continue
  case $(cat "$f") in running) running=$((running+1));; turn-ended) ended=$((ended+1));; esac
done
unread=0; [ -s "$st/inbox.md" ] && unread=$(grep -c . "$st/inbox.md")
printf 'railyard: %s %d engine(s) running, %d turn-ended, %d unread inbox line(s). Read with bin/ry-inbox.sh.\n' \
  "$standing" "$running" "$ended" "$unread"
