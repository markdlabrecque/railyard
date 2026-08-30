#!/usr/bin/env bash
# Open the yard: a tmux session "railyard" with the yardmaster (claude) in
# window "yard", started from this repo so AGENTS.md and the hooks load.
# Attaches to the session. Re-running attaches to the existing one.
# usage: ry-yard.sh
set -euo pipefail
# shellcheck source=bin/ry-lib.sh
. "$(dirname "$0")/ry-lib.sh"
# shellcheck source=bin/ry-tmux-lib.sh
. "$(dirname "$0")/ry-tmux-lib.sh"
case ${1:-} in -h|--help) ry_usage "$0"; exit 0 ;; esac
home=$(ry_home); s=$(ry_tmux_session)
if ! ry_tmux has-session -t "=$s" 2>/dev/null; then
  ry_tmux new-session -d -s "$s" -n yard -c "$home" \
    "export CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false RY_HOME=$(printf %q "$home"); claude"
fi
if [ -n "${TMUX:-}" ]; then ry_tmux switch-client -t "=$s"; else ry_tmux attach -t "=$s"; fi
