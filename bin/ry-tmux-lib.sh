#!/usr/bin/env bash
# tmux backend primitives. One railyard session (RY_TMUX_SESSION, default
# "railyard"); one window per engine named ry-<id>. RY_TMUX_SOCKET selects a
# private server (-L) so tests never touch the user's tmux.

ry_tmux() {
  if [ -n "${RY_TMUX_SOCKET:-}" ]; then tmux -L "$RY_TMUX_SOCKET" "$@"; else tmux "$@"; fi
}

ry_tmux_session() { printf '%s\n' "${RY_TMUX_SESSION:-railyard}"; }

ry_tmux_ensure_session() {
  local s; s=$(ry_tmux_session)
  ry_tmux has-session -t "=$s" 2>/dev/null || ry_tmux new-session -d -s "$s" -n yard
}

ry_tmux_has_window() {  # <name>
  ry_tmux list-windows -t "=$(ry_tmux_session)" -F '#W' 2>/dev/null | grep -qx -- "$1"
}

ry_tmux_open_window() {  # <name> <cwd> <shell-command>
  ry_tmux_ensure_session
  ry_tmux new-window -d -t "=$(ry_tmux_session)" -n "$1" -c "$2" "$3"
}

ry_tmux_kill_window() {  # <name>
  ry_tmux_has_window "$1" && ry_tmux kill-window -t "=$(ry_tmux_session):$1"
  return 0
}
