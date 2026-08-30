#!/usr/bin/env bats
load helpers
setup() { setup_home; setup_orca; make_project xyz; }
teardown() { pid=$(cat "$RY_HOME/state/.watch.lock" 2>/dev/null); [ -n "$pid" ] && kill "$pid" 2>/dev/null || true; }

@test "orca dispatch registers the repo once and opens a terminal in the siding" {
  run ry-dispatch.sh --haul xyz "fix it"
  [ "$status" -eq 0 ]
  id=$(sed -n 's/^id=//p' <<<"$output")
  grep -q -- "repo add --path $RY_HOME/projects/xyz" "$RY_FAKE_ORCA_LOG"
  grep -q -- "terminal create --worktree path:$RY_HOME/yard/xyz/$id --title ry-$id --command " "$RY_FAKE_ORCA_LOG"
  grep -q -- "--dangerously-skip-permissions --settings $RY_HOME/state/$id.settings.json" "$RY_FAKE_ORCA_LOG"
  grep -q '^backend=orca$' "$RY_HOME/state/$id.meta"
  grep -q '^target=term_fake_' "$RY_HOME/state/$id.meta"
  [ "$(cat "$RY_HOME/state/$id.status")" = "running" ]
  # second dispatch: repo already known -> no second repo add
  printf '{"path":"%s"}' "$RY_HOME/projects/xyz" > "$RY_FAKE_ORCA_REPOS"
  ry-dispatch.sh --haul xyz "again" >/dev/null
  [ "$(grep -c "repo add" "$RY_FAKE_ORCA_LOG")" -eq 1 ]
}

@test "orca decouple stops the siding's terminals" {
  id=$(ry-dispatch.sh --haul xyz "x" | sed -n 's/^id=//p')
  run ry-decouple.sh --force "$id"
  [ "$status" -eq 0 ]
  grep -q -- "terminal stop --worktree path:$RY_HOME/yard/xyz/$id" "$RY_FAKE_ORCA_LOG"
}

@test "orca wake: session start records ORCA_TERMINAL_HANDLE and watch sends to it" {
  ORCA_TERMINAL_HANDLE=term_ym run ry-session-start.sh <<<'{}'
  [ "$(cat "$RY_HOME/state/yardmaster.orca")" = "term_ym" ]
  kill "$(cat "$RY_HOME/state/.watch.lock")"
  id=$(ry-dispatch.sh --haul xyz "x" | sed -n 's/^id=//p')
  RY_ID=$id ry-engine-stop.sh <<<"{\"transcript_path\":\"$BATS_TEST_DIRNAME/fixtures/transcript.jsonl\",\"stop_hook_active\":false}"
  run ry-watch.sh --once
  grep -q -- "terminal send --terminal term_ym --text \[railyard\] engine $id turn-ended: DONE" "$RY_FAKE_ORCA_LOG"
  grep -q -- "--enter" "$RY_FAKE_ORCA_LOG"
}

@test "peek and send work through the backend" {
  id=$(ry-dispatch.sh --haul xyz "x" | sed -n 's/^id=//p')
  run ry-peek.sh "$id"
  [ "$status" -eq 0 ]; [[ "$output" == *"line two"* ]]
  run ry-send.sh "$id" "please also update the docs"
  [ "$status" -eq 0 ]
  grep -q -- "terminal send --terminal term_fake_.* --text please also update the docs --enter" "$RY_FAKE_ORCA_LOG"
  [ "$(cat "$RY_HOME/state/$id.status")" = "running" ]
}

@test "unknown backend is refused before laying track side effects are launched" {
  RY_BACKEND=zellij run ry-dispatch.sh --haul xyz "x"
  [ "$status" -ne 0 ]
}
