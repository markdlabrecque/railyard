#!/usr/bin/env bats
load helpers

setup() {
  setup_home; make_project xyz
  ID=$(ry-dispatch.sh --haul xyz "task" | sed -n 's/^id=//p')
  T="$BATS_TEST_DIRNAME/fixtures/transcript.jsonl"
}
teardown() { teardown_tmux; }

end_turn() { RY_ID=$1 ry-engine-stop.sh <<<"{\"transcript_path\":\"$T\",\"stop_hook_active\":false}"; }

@test "watch --once turns a turn-ended event into an inbox line, once" {
  end_turn "$ID"
  run ry-watch.sh --once
  [ "$status" -eq 0 ]
  grep -q "engine $ID turn-ended: DONE: added HELLO.md and committed it.$" "$RY_HOME/state/inbox.md"
  run ry-watch.sh --once
  [ "$(grep -c "$ID" "$RY_HOME/state/inbox.md")" -eq 1 ]
}

@test "watch injects the line into the yardmaster pane when one is recorded" {
  setup_tmux
  out="$BATS_TEST_TMPDIR/pane.out"
  tmux -L "$RY_TMUX_SOCKET" new-session -d -s ym "cat > $out"
  tmux -L "$RY_TMUX_SOCKET" display -p -t ym '#{pane_id}' > "$RY_HOME/state/yardmaster.pane"
  end_turn "$ID"
  run ry-watch.sh --once
  [ "$status" -eq 0 ]
  for _ in $(seq 1 30); do grep -q "$ID" "$out" 2>/dev/null && break; sleep 0.1; done
  grep -q "engine $ID turn-ended" "$out"
}

@test "watch survives a dead pane and still writes the inbox" {
  echo '%999' > "$RY_HOME/state/yardmaster.pane"
  end_turn "$ID"
  run ry-watch.sh --once
  [ "$status" -eq 0 ]
  grep -q "$ID" "$RY_HOME/state/inbox.md"
}

@test "watch flags a running engine that has been silent too long, once" {
  echo running > "$RY_HOME/state/$ID.status"
  touch -t 202001010000 "$RY_HOME/state/$ID.status"
  RY_STALL_MIN=5 run ry-watch.sh --once
  grep -q "engine $ID silent for" "$RY_HOME/state/inbox.md"
  RY_STALL_MIN=5 run ry-watch.sh --once
  [ "$(grep -c "silent" "$RY_HOME/state/inbox.md")" -eq 1 ]
}

@test "watch does not flag a fresh running engine" {
  echo running > "$RY_HOME/state/$ID.status"
  run ry-watch.sh --once
  [ ! -s "$RY_HOME/state/inbox.md" ]
}
