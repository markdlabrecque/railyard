#!/usr/bin/env bash
# Open the yard: the yardmaster (claude) started from this repo so AGENTS.md
# and the hooks load. tmux: session "railyard", window "yard" — attaches, and
# re-running re-attaches. orca: a focused Orca terminal in this repo.
#
# RY_TMUX_SESSION names the tmux session, so a second clone can run a second
# yard side by side; it travels into the yardmaster so its engines open there
# too.
#
# usage: ry-yard.sh [--dry-run]
#   --dry-run  print the command the yard would start, and exit
set -euo pipefail
# shellcheck source=bin/ry-lib.sh
. "$(dirname "$0")/ry-lib.sh"
# shellcheck source=bin/ry-backend-lib.sh
. "$(dirname "$0")/ry-backend-lib.sh"
case ${1:-} in -h|--help) ry_usage "$0"; exit 0 ;; esac

home=$(ry_home); ry_backend_check
cmd="export CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false RY_BACKEND=$(ry_backend) $(ry_env_exports); claude"
if [ "${1:-}" = --dry-run ]; then printf '%s\n' "$cmd"; exit 0; fi

case $(ry_backend) in
  tmux)
    s=$(ry_tmux_session)
    ry_tmux has-session -t "=$s" 2>/dev/null || ry_tmux new-session -d -s "$s" -n yard -c "$home" "$cmd"
    if [ -n "${TMUX:-}" ]; then ry_tmux switch-client -t "=$s"; else ry_tmux attach -t "=$s"; fi ;;
  cmux)
    ws=$(ry_cmux_open yardmaster "$home" "$cmd")
    echo "yardmaster opened in cmux: $ws" ;;
  orca)
    ry_orca_ensure_repo "$home"
    out=$(orca terminal create --worktree "path:$home" --title yardmaster --command "$cmd" --focus --json)
    ry_orca_ok "$out"; echo "yardmaster opened in Orca: $(jq -r '.result.terminal.handle' <<<"$out")" ;;
  *) ry_die "ry-yard.sh supports tmux, orca or cmux" ;;
esac
