#!/usr/bin/env bash
# Yardmaster SessionStart hook: claim the yard for this session, make sure one
# watcher daemon is running, and print a short yard summary that lands in the
# session context.
#
# One session holds the yard at a time. The claim is the tmux pane the watcher
# nudges to wake it, in state/yardmaster.pane. A session that starts while
# another live pane holds the yard is told so rather than silently stealing it:
# two yardmasters share one inbox and take work from each other.
# usage: Claude SessionStart hook, run from the railyard home.
set -uo pipefail
# shellcheck source=bin/ry-lib.sh
. "$(dirname "$0")/ry-lib.sh"
# shellcheck source=bin/ry-tmux-lib.sh
. "$(dirname "$0")/ry-tmux-lib.sh"
case ${1:-} in -h|--help) ry_usage "$0"; exit 0 ;; esac
home=$(ry_home); st="$home/state"; bindir=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$st"
cat >/dev/null || true   # drain hook stdin

held=$(cat "$st/yardmaster.pane" 2>/dev/null || true)
if [ -n "$held" ] && ! ry_tmux display -p -t "$held" '#{pane_id}' >/dev/null 2>&1; then
  held=""   # the pane that held the yard is gone
fi

if [ -n "${TMUX_PANE:-}" ] && { [ -z "$held" ] || [ "$held" = "$TMUX_PANE" ]; }; then
  printf '%s\n' "$TMUX_PANE" > "$st/yardmaster.pane"
  standing="you are the yardmaster."
elif [ -n "$held" ]; then
  standing="another yardmaster holds the yard (pane $held). Do not dispatch or act on the inbox — you would take work from it. Ask the dispatcher before taking over."
else
  standing="you are the yardmaster, but no tmux pane holds the yard, so the watcher cannot wake you. Check bin/ry-manifest.sh yourself instead of ending your turn to wait."
fi

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
printf 'railyard: %s %d engine(s) running, %d turn-ended, %d unread inbox line(s). Read with bin/ry-inbox.sh.\n' \
  "$standing" "$running" "$ended" "$unread"
