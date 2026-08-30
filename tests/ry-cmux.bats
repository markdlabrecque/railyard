#!/usr/bin/env bats
load helpers
setup() { setup_home; setup_cmux; make_project xyz; }
teardown() { pid=$(cat "$RY_HOME/state/.watch.lock" 2>/dev/null); [ -n "$pid" ] && kill "$pid" 2>/dev/null || true; }

@test "cmux dispatch opens a named workspace on the siding and records its uuid" {
  run ry-dispatch.sh --haul xyz "fix it"
  [ "$status" -eq 0 ]
  id=$(sed -n 's/^id=//p' <<<"$output")
  grep -q -- "new-workspace --name ry-$id --cwd $RY_HOME/yard/xyz/$id --command " "$RY_FAKE_CMUX_LOG"
  grep -q -- "--dangerously-skip-permissions --settings $RY_HOME/state/$id.settings.json" "$RY_FAKE_CMUX_LOG"
  grep -q '^backend=cmux$' "$RY_HOME/state/$id.meta"
  # the uuid, not the positional "workspace:1" ref cmux prints
  grep -q '^target=ws-fake-' "$RY_HOME/state/$id.meta"
  [ "$(cat "$RY_HOME/state/$id.status")" = "running" ]
}

@test "cmux decouple closes the workspace" {
  id=$(ry-dispatch.sh --haul xyz "x" | sed -n 's/^id=//p')
  target=$(sed -n 's/^target=//p' "$RY_HOME/state/$id.meta")
  run ry-decouple.sh --force "$id"
  [ "$status" -eq 0 ]
  grep -q -- "close-workspace --workspace $target" "$RY_FAKE_CMUX_LOG"
}

@test "cmux peek and send work through the backend" {
  id=$(ry-dispatch.sh --haul xyz "x" | sed -n 's/^id=//p')
  target=$(sed -n 's/^target=//p' "$RY_HOME/state/$id.meta")
  run ry-peek.sh "$id"
  [ "$status" -eq 0 ]; [[ "$output" == *"line two"* ]]
  grep -q -- "read-screen --workspace $target" "$RY_FAKE_CMUX_LOG"
  run ry-send.sh "$id" "please also update the docs"
  [ "$status" -eq 0 ]
  grep -q -- "send --workspace $target -- please also update the docs" "$RY_FAKE_CMUX_LOG"
  grep -q -- "send-key --workspace $target -- enter" "$RY_FAKE_CMUX_LOG"
  [ "$(cat "$RY_HOME/state/$id.status")" = "running" ]
}

@test "cmux wake: session start records CMUX_WORKSPACE_ID and watch sends to it" {
  CMUX_WORKSPACE_ID=ws-ym run ry-session-start.sh <<<'{}'
  [ "$(cat "$RY_HOME/state/yardmaster.cmux")" = "ws-ym" ]
  kill "$(cat "$RY_HOME/state/.watch.lock")"
  id=$(ry-dispatch.sh --haul xyz "x" | sed -n 's/^id=//p')
  RY_ID=$id ry-engine-stop.sh <<<"{\"transcript_path\":\"$BATS_TEST_DIRNAME/fixtures/transcript.jsonl\",\"stop_hook_active\":false}"
  run ry-watch.sh --once
  grep -q -- "send --workspace ws-ym -- \[railyard\] engine $id turn-ended: DONE" "$RY_FAKE_CMUX_LOG"
}

@test "a second cmux session is told another yardmaster holds the yard" {
  printf 'ws-first yardmaster\n' >> "$RY_FAKE_CMUX_WS"   # cmux still shows it
  CMUX_WORKSPACE_ID=ws-first ry-session-start.sh <<<'{}' >/dev/null
  CMUX_WORKSPACE_ID=ws-second run ry-session-start.sh <<<'{}'
  [[ "$output" == *"another yardmaster"* ]]
  [ "$(cat "$RY_HOME/state/yardmaster.cmux")" = "ws-first" ]
}

@test "a cmux session takes the yard when the holding workspace is gone" {
  printf 'ws-first yardmaster\n' >> "$RY_FAKE_CMUX_WS"
  CMUX_WORKSPACE_ID=ws-first ry-session-start.sh <<<'{}' >/dev/null
  : > "$RY_FAKE_CMUX_WS"   # that workspace was closed
  CMUX_WORKSPACE_ID=ws-second run ry-session-start.sh <<<'{}'
  [[ "$output" == *"you are the yardmaster"* ]]
  [ "$(cat "$RY_HOME/state/yardmaster.cmux")" = "ws-second" ]
}

@test "ry-yard.sh --dry-run carries the cmux backend into the yardmaster" {
  run ry-yard.sh --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"RY_BACKEND=cmux"* ]]
}
