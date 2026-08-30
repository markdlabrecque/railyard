#!/usr/bin/env bats
load helpers

setup() {
  setup_home; make_project xyz
  ID=$(ry-dispatch.sh --haul xyz "task" | sed -n 's/^id=//p')
  export RY_ID=$ID
  T="$BATS_TEST_DIRNAME/fixtures/transcript.jsonl"
}

@test "stop hook marks turn-ended, logs event, captures last assistant text" {
  run ry-engine-stop.sh <<<"{\"session_id\":\"s1\",\"transcript_path\":\"$T\",\"stop_hook_active\":false}"
  [ "$status" -eq 0 ]
  [ "$(cat "$RY_HOME/state/$ID.status")" = "turn-ended" ]
  grep -q " $ID turn-ended$" "$RY_HOME/state/events.log"
  [ "$(head -n1 "$RY_HOME/state/$ID.last.md")" = "DONE: added HELLO.md and committed it." ]
  [ "$(tail -n1 "$RY_HOME/state/$ID.last.md")" = "- Nothing pushed." ]
}

@test "stop hook is a no-op when stop_hook_active is true" {
  run ry-engine-stop.sh <<<"{\"session_id\":\"s1\",\"transcript_path\":\"$T\",\"stop_hook_active\":true}"
  [ "$status" -eq 0 ]
  [ "$(cat "$RY_HOME/state/$ID.status")" = "dispatched" ]
  [ ! -e "$RY_HOME/state/events.log" ]
}

@test "stop hook never fails the engine, even with bad input" {
  run ry-engine-stop.sh <<<"not json"
  [ "$status" -eq 0 ]
  RY_ID= run ry-engine-stop.sh <<<"{}"
  [ "$status" -eq 0 ]
}
