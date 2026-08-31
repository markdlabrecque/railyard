#!/usr/bin/env bash
# Backend seam. RY_BACKEND=tmux (default) | orca | cmux | herdr | none. Every backend answers
# the same five questions: open an engine terminal, stop it, peek at it, send
# it text, and nudge the yardmaster. The engine's backend and target are
# recorded in its meta (backend=, target=) so later calls need no env.
# shellcheck source=bin/ry-tmux-lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/ry-tmux-lib.sh"
# shellcheck source=bin/ry-orca-lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/ry-orca-lib.sh"
# shellcheck source=bin/ry-cmux-lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/ry-cmux-lib.sh"
# shellcheck source=bin/ry-herdr-lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/ry-herdr-lib.sh"

ry_backend() { printf '%s\n' "${RY_BACKEND:-tmux}"; }

ry_backend_check() {
  case $(ry_backend) in
    tmux|none) ;;
    orca) command -v orca >/dev/null || ry_die "RY_BACKEND=orca but the orca CLI is not installed" ;;
    cmux) ry_cmux_available || ry_die "RY_BACKEND=cmux but the cmux CLI was not found" ;;
    herdr) ry_herdr_available || ry_die "RY_BACKEND=herdr but the herdr CLI is not installed"
           ry_herdr_running || ry_die "RY_BACKEND=herdr but no herdr server is running" ;;
    *) ry_die "unknown RY_BACKEND '$(ry_backend)' (tmux|orca|cmux|herdr|none)" ;;
  esac
}

ry_backend_open() {  # <id> <siding> <command> -> target
  case $(ry_backend) in
    tmux) ry_tmux_open_window "ry-$1" "$2" "$3"; printf 'ry-%s\n' "$1" ;;
    orca) ry_orca_ensure_repo "$(ry_project_dir "$(ry_meta_get "$1" project)")"
          ry_orca_open "ry-$1" "$2" "$3" ;;
    cmux) ry_cmux_open "ry-$1" "$2" "$3" ;;
    herdr) ry_herdr_open "ry-$1" "$2" "$3" ;;
    none) ry_die "RY_BACKEND=none: nothing to launch" ;;
  esac
}

ry_backend_stop() {  # <id>
  local backend target siding
  backend=$(ry_meta_get "$1" backend); target=$(ry_meta_get "$1" target); siding=$(ry_meta_get "$1" siding)
  case $backend in
    tmux) [ -n "$target" ] && ry_tmux_kill_window "$target" ;;
    orca) ry_orca_stop_siding "$siding" ;;
    cmux) [ -n "$target" ] && ry_cmux_close "$target" ;;
    herdr) [ -n "$target" ] && ry_herdr_close "$target" ;;
  esac
  return 0
}

ry_backend_peek() {  # <id> -> recent terminal output
  local target; target=$(ry_meta_get "$1" target)
  case $(ry_meta_get "$1" backend) in
    tmux) ry_tmux capture-pane -p -t "=$(ry_tmux_session):$target" ;;
    orca) ry_orca_read "$target" ;;
    cmux) ry_cmux_read "$target" ;;
    herdr) ry_herdr_read "$target" ;;
    *) ry_die "engine $1 has no terminal" ;;
  esac
}

ry_backend_send() {  # <id> <text>
  local target; target=$(ry_meta_get "$1" target)
  case $(ry_meta_get "$1" backend) in
    tmux) ry_tmux send-keys -t "=$(ry_tmux_session):$target" -l -- "$2" && ry_tmux send-keys -t "=$(ry_tmux_session):$target" Enter ;;
    orca) ry_orca_send "$target" "$2" ;;
    cmux) ry_cmux_send "$target" "$2" ;;
    herdr) ry_herdr_send "$target" "$2" ;;
    *) ry_die "engine $1 has no terminal" ;;
  esac
}

# One session holds the yard at a time, and the claim is the terminal the
# watcher nudges to wake it. Each backend names its own terminals, so a claim
# is a pair: which backend, and which terminal in it. Both live in one file,
# state/yardmaster.claim, so the watcher reads one place no matter how many
# backends exist — and so a yard opened in two backends is a visible collision
# rather than two claims that never see each other.

ry_backend_self() {  # -> this session's terminal id, empty if it has none
  case $(ry_backend) in
    orca) printf '%s\n' "${ORCA_TERMINAL_HANDLE:-}" ;;
    cmux) printf '%s\n' "${CMUX_WORKSPACE_ID:-}" ;;
    herdr) printf '%s\n' "${HERDR_PANE_ID:-}" ;;
    *)    printf '%s\n' "${TMUX_PANE:-}" ;;
  esac
}

ry_backend_claim_file() {  # -> the one file holding the yard claim
  printf '%s\n' "$(ry_home)/state/yardmaster.claim"
}

ry_claim_get() {  # <field>: backend|target -> its value, empty if unclaimed
  local f; f=$(ry_backend_claim_file)
  [ -f "$f" ] || return 0   # unclaimed is an answer, not a failure
  sed -n "s/^$1=//p" "$f" | tail -n 1
}

ry_claim_write() {  # <backend> <target>
  local st; st="$(ry_home)/state"
  printf 'backend=%s\ntarget=%s\n' "$1" "$2" > "$(ry_backend_claim_file)"
  # the per-backend files this replaced; leaving them would claim the yard twice
  rm -f "$st/yardmaster.pane" "$st/yardmaster.orca" "$st/yardmaster.cmux" "$st/yardmaster.herdr"
}

ry_claim_alive() {  # <backend> <target>: is that terminal still there?
  [ -n "${2:-}" ] || return 1
  case $1 in
    orca) command -v orca >/dev/null 2>&1 &&
          orca terminal read --terminal "$2" --json >/dev/null 2>&1 ;;
    cmux) ry_cmux_available && ry_cmux_alive "$2" ;;
    herdr) ry_herdr_available && ry_herdr_alive "$2" ;;
    # `display -t <pane>` exits 0 for a pane that is gone, so ask for the list
    *)    ry_tmux list-panes -a -F '#{pane_id}' 2>/dev/null | grep -qxF -- "$2" ;;
  esac
}

ry_claim_send() {  # <backend> <target> <text>: best effort, never fails
  case $1 in
    orca) command -v orca >/dev/null 2>&1 &&
          orca terminal send --terminal "$2" --text "$3" --enter --json >/dev/null 2>&1 ;;
    cmux) ry_cmux_available && ry_cmux_send "$2" "$3" >/dev/null 2>&1 ;;
    herdr) ry_herdr_available && ry_herdr_send "$2" "$3" >/dev/null 2>&1 ;;
    *)    ry_tmux send-keys -t "$2" -l -- "$3" && ry_tmux send-keys -t "$2" Enter ;;
  esac
  return 0
}

ry_backend_nudge() {  # <text>: best effort, never fails
  local backend target
  backend=$(ry_claim_get backend); target=$(ry_claim_get target)
  [ -n "$target" ] || return 0
  ry_claim_alive "$backend" "$target" || return 0
  ry_claim_send "$backend" "$target" "$1"
  return 0
}
