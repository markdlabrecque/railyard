#!/usr/bin/env bats
load helpers

setup() { setup_home; setup_tmux; make_project xyz; }
teardown() { teardown_tmux; }

wait_for_log() { for _ in $(seq 1 50); do [ -s "$RY_FAKE_CLAUDE_LOG" ] && return 0; sleep 0.1; done; return 1; }

@test "dispatch with tmux backend opens window ry-<id> running claude in the siding" {
  run ry-dispatch.sh --haul xyz "fix the login test"
  [ "$status" -eq 0 ]
  id=$(sed -n 's/^id=//p' <<<"$output")
  tmux -L "$RY_TMUX_SOCKET" list-windows -t railyard -F '#W' | grep -qx "ry-$id"
  wait_for_log
  [ "$(sed -n 1p "$RY_FAKE_CLAUDE_LOG")" = "$RY_HOME/yard/xyz/$id" ]
  args=$(sed -n '2,$p' "$RY_FAKE_CLAUDE_LOG")
  [[ "$args" == *"--dangerously-skip-permissions"* ]]
  [[ "$args" == *"--settings $RY_HOME/state/$id.settings.json"* ]]
  [[ "$args" == *"fix the login test"* ]]
  [ "$(cat "$RY_HOME/state/$id.status")" = "running" ]
  grep -q "^window=ry-$id$" "$RY_HOME/state/$id.meta"
}

@test "engine settings file wires the Stop hook to ry-engine-stop.sh" {
  id=$(ry-dispatch.sh --haul xyz "x" | sed -n 's/^id=//p')
  jq -e '.hooks.Stop[0].hooks[0].command | test("ry-engine-stop.sh")' "$RY_HOME/state/$id.settings.json"
}

@test "decouple kills the tmux window" {
  id=$(ry-dispatch.sh --haul xyz "x" | sed -n 's/^id=//p')
  run ry-decouple.sh --force "$id"
  [ "$status" -eq 0 ]
  ! tmux -L "$RY_TMUX_SOCKET" list-windows -t railyard -F '#W' 2>/dev/null | grep -qx "ry-$id"
}

@test "RY_ENGINE_CMD overrides the engine command" {
  RY_ENGINE_CMD="claude --model haiku" run ry-dispatch.sh --haul xyz "x"
  [ "$status" -eq 0 ]
  wait_for_log
  [[ "$(sed -n 2p "$RY_FAKE_CLAUDE_LOG")" == "--model haiku"* ]]
}

@test "launch pre-trusts the siding in claude.json" {
  export RY_CLAUDE_JSON="$BATS_TEST_TMPDIR/claude.json"
  echo '{"projects":{"/other":{"hasTrustDialogAccepted":true}},"foo":1}' > "$RY_CLAUDE_JSON"
  id=$(ry-dispatch.sh --haul xyz "x" | sed -n 's/^id=//p')
  jq -e --arg p "$RY_HOME/yard/xyz/$id" '.projects[$p].hasTrustDialogAccepted == true and .projects["/other"].hasTrustDialogAccepted == true and .foo == 1' "$RY_CLAUDE_JSON"
}

@test "launch creates claude.json when missing" {
  export RY_CLAUDE_JSON="$BATS_TEST_TMPDIR/new.json"
  id=$(ry-dispatch.sh --haul xyz "x" | sed -n 's/^id=//p')
  jq -e --arg p "$RY_HOME/yard/xyz/$id" '.projects[$p].hasTrustDialogAccepted == true' "$RY_CLAUDE_JSON"
}

@test "engine prompt = preamble with id/branch/report filled in + waybill" {
  id=$(ry-dispatch.sh --survey xyz "why is CI slow" | sed -n 's/^id=//p')
  for _ in $(seq 1 50); do [ -s "$RY_FAKE_CLAUDE_LOG" ] && break; sleep 0.1; done
  args=$(sed -n '2,$p' "$RY_FAKE_CLAUDE_LOG")
  [[ "$args" == *"ry/$id"* ]]
  [[ "$args" == *"$RY_HOME/data/$id/report.md"* ]]
  [[ "$args" == *"why is CI slow"* ]]
  [[ "$args" != *"{{"* ]]
  [ -d "$RY_HOME/data/$id" ]
}
