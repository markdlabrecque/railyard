#!/usr/bin/env bash
# Open the yard: a tmux session "railyard" with the yardmaster (claude) in
# window "yard", started from this repo so AGENTS.md and the hooks load.
# Attaches to the session. Re-running attaches to the existing one.
#
# RY_TMUX_SESSION names the session, so a second clone can run a second yard
# side by side; it travels into the yardmaster so its engines open there too.
#
# usage: ry-yard.sh [--dry-run]
#   --dry-run  print the command the yard would start, and exit
set -euo pipefail
# shellcheck source=bin/ry-lib.sh
. "$(dirname "$0")/ry-lib.sh"
# shellcheck source=bin/ry-tmux-lib.sh
. "$(dirname "$0")/ry-tmux-lib.sh"
case ${1:-} in -h|--help) ry_usage "$0"; exit 0 ;; esac
home=$(ry_home); s=$(ry_tmux_session)
cmd="export CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false $(ry_env_exports); claude"
if [ "${1:-}" = --dry-run ]; then printf '%s\n' "$cmd"; exit 0; fi
if ! ry_tmux has-session -t "=$s" 2>/dev/null; then
  ry_tmux new-session -d -s "$s" -n yard -c "$home" "$cmd"
fi
if [ -n "${TMUX:-}" ]; then ry_tmux switch-client -t "=$s"; else ry_tmux attach -t "=$s"; fi
