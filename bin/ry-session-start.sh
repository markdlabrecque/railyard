#!/usr/bin/env bash
# Yardmaster SessionStart hook: claim the yard for this session, make sure one
# watcher daemon is running, and print a short yard summary that lands in the
# session context.
#
# One session holds the yard at a time. The claim is the terminal the watcher
# nudges to wake it, recorded in state/yardmaster.claim as the backend plus the
# terminal id within it. A session that starts while another live terminal
# holds the yard is told so rather than silently stealing it: two yardmasters
# share one inbox and take work from each other. Because the claim names its
# backend, a session that starts on a different backend from the one holding
# the yard is told that too, instead of quietly claiming alongside it.
#
# An engine stands down (RY_ID set). A siding cut from railyard itself carries
# railyard's own .claude/settings.json, so this hook fires inside the engine —
# and the engine's RY_HOME points at the live yard, not its siding. Without
# this guard the engine claims the yard out from under the yardmaster and
# starts a second watcher on it. Same guard as ry-turnend-guard.sh.
# usage: Claude SessionStart hook, run from the railyard home.
set -uo pipefail
# shellcheck source=bin/ry-lib.sh
. "$(dirname "$0")/ry-lib.sh"
# shellcheck source=bin/ry-backend-lib.sh
. "$(dirname "$0")/ry-backend-lib.sh"
case ${1:-} in -h|--help) ry_usage "$0"; exit 0 ;; esac
[ -z "${RY_ID:-}" ] || exit 0
home=$(ry_home); st="$home/state"; bindir=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$st"
cat >/dev/null || true   # drain hook stdin

backend=$(ry_backend); self=$(ry_backend_self)
held_backend=$(ry_claim_get backend); held=$(ry_claim_get target)
if [ -n "$held" ] && ! ry_claim_alive "$held_backend" "$held"; then
  held=""; held_backend=""   # the terminal that held the yard is gone
fi

# The claim we would be standing down to is a live terminal, so handing the
# yard over needs --force. Print the whole line: a stood-down session should
# not have to go looking for the one command that could change its standing.
take="bin/ry-claim.sh --take --force"

if [ -n "$self" ] && { [ -z "$held" ] || { [ "$held" = "$self" ] && [ "$held_backend" = "$backend" ]; }; }; then
  ry_claim_write "$backend" "$self"
  standing="you are the yardmaster."
elif [ -n "$held" ] && [ "$held_backend" != "$backend" ]; then
  standing="another yardmaster holds the yard on the $held_backend backend ($held), and this session is on $backend. One yard runs on one backend — do not dispatch or act on the inbox. Ask the dispatcher which backend this yard should use; on their word, $take."
elif [ -n "$held" ]; then
  standing="another yardmaster holds the yard ($held). Do not dispatch or act on the inbox — you would take work from it. Ask the dispatcher before taking over; on their word, $take."
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
# data/learnings.md is a queue, not an archive: /shed files into it, and the
# next session start, /manifest or /allaboard empties it by promoting each line
# somewhere that enforces it or dropping it. Unprocessed lines are worth a word
# in the summary for the same reason unread inbox lines are.
learnings=0
[ -f "$home/data/learnings.md" ] && learnings=$(grep -c '^- ' "$home/data/learnings.md" || true)
# state/open-decisions.md mirrors data/learnings.md but for live-state items
# awaiting the dispatcher's word: unanswered decisions, undispatched asks, and
# review judgments a fresh session would otherwise have to re-derive. Same
# queue discipline, same reason to flag it in the summary.
decisions=0
[ -f "$st/open-decisions.md" ] && decisions=$(grep -c '^- ' "$st/open-decisions.md" || true)
# A fresh clone has neither data/yard.md nor data/projects.md: both are
# machine-local and gitignored, so they do not travel with the repo. The
# readers fall back (tmux, no projects) and would say nothing, which is the
# same silent-wrong-value failure that got those files untracked in the first
# place. So say it once, as a notice and not an error — dispatching still
# works. Either file existing means the yard is configured on purpose, and the
# notice goes quiet. Only a clone gets it: a yard home that is not a git
# checkout is a test fixture or a scratch home, not somebody's first run.
firstrun=""
if [ -e "$home/.git" ] && [ ! -f "$home/data/yard.md" ] && [ ! -f "$home/data/projects.md" ]; then
  firstrun=" First run: this clone has no data/yard.md and no data/projects.md — both are machine-local and gitignored, so a clone never carries them. Until they exist this is a tmux yard with no projects registered; tell the dispatcher, and see docs/guide.md § First run."
fi

printf 'railyard: %s %d engine(s) running, %d turn-ended, %d unread inbox line(s). Read with bin/ry-inbox.sh.%s' \
  "$standing" "$running" "$ended" "$unread" "$firstrun"
if [ "$learnings" -gt 0 ]; then
  printf ' %d unfiled learning(s) in data/learnings.md: promote or drop each one (AGENTS.md § Learnings).' "$learnings"
fi
if [ "$decisions" -gt 0 ]; then
  printf ' %d open decision(s) in state/open-decisions.md: bring them to the dispatcher (AGENTS.md § Learnings).' "$decisions"
fi
printf '\n'
