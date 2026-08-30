#!/usr/bin/env bash
# cmux backend primitives. Railyard keeps its own sidings; cmux just hosts the
# terminal: one cmux workspace per engine, opened on the siding with `cmux
# new-workspace --cwd <siding> --command <cmd>`. Inside cmux terminals
# CMUX_WORKSPACE_ID names the yardmaster's own workspace.
#
# cmux prints positional refs ("workspace:1") that renumber when a workspace
# closes, so nothing positional is ever stored: after creating a workspace we
# look its stable uuid up by the title we gave it.
#
# The control socket only accepts processes started inside cmux, which a yard
# hosted in cmux satisfies (CMUX_SOCKET_PATH and CMUX_SOCKET_PASSWORD are
# inherited by every process it spawns, the watcher included). Driving cmux
# from outside needs socketControlMode raised in cmux.json, and RY_CMUX_PASSWORD
# is passed through for that case.

RY_CMUX_APP_BIN=/Applications/cmux.app/Contents/Resources/bin/cmux

ry_cmux() {  # the cmux CLI, wherever it lives
  local bin=${RY_CMUX_BIN:-}
  if [ -z "$bin" ]; then
    if command -v cmux >/dev/null 2>&1; then bin=cmux
    else bin=$RY_CMUX_APP_BIN; fi
  fi
  if [ -n "${RY_CMUX_PASSWORD:-}" ]; then
    "$bin" --password "$RY_CMUX_PASSWORD" "$@"
  else
    "$bin" "$@"
  fi
}

ry_cmux_available() {  # is the CLI there at all
  [ -n "${RY_CMUX_BIN:-}" ] || command -v cmux >/dev/null 2>&1 || [ -x "$RY_CMUX_APP_BIN" ]
}

ry_cmux_workspace_id() {  # <title> -> the workspace's stable uuid, if cmux knows it
  ry_cmux --json --id-format uuids list-workspaces 2>/dev/null \
    | jq -r --arg t "$1" 'first(.workspaces[]? | select(.title == $t) | .id) // empty' 2>/dev/null
}

ry_cmux_open() {  # <title> <cwd> <command> -> workspace uuid
  local out id
  out=$(ry_cmux new-workspace --name "$1" --cwd "$2" --command "$3" --focus false) \
    || ry_die "cmux: could not create a workspace for $1"
  id=$(ry_cmux_workspace_id "$1")
  # fall back to whatever handle the create printed ("OK <handle>")
  [ -n "$id" ] || id=$(sed -n 's/^OK \([^ ]*\).*/\1/p' <<<"$out")
  [ -n "$id" ] || ry_die "cmux: created a workspace for $1 but could not resolve its id"
  printf '%s\n' "$id"
}

ry_cmux_close() {  # <workspace>
  ry_cmux close-workspace --workspace "$1" >/dev/null 2>&1 || true
}

ry_cmux_read() {  # <workspace> -> recent terminal text
  ry_cmux read-screen --workspace "$1" --lines 200
}

ry_cmux_send() {  # <workspace> <text>
  ry_cmux send --workspace "$1" -- "$2" >/dev/null || ry_die "cmux: send to $1 failed"
  ry_cmux send-key --workspace "$1" -- enter >/dev/null || ry_die "cmux: enter to $1 failed"
}

ry_cmux_alive() {  # <workspace>
  ry_cmux --json --id-format uuids list-workspaces 2>/dev/null \
    | jq -e --arg i "$1" 'any(.workspaces[]?; .id == $i)' >/dev/null 2>&1
}
