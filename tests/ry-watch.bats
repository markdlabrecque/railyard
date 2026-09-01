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
  hold_yard tmux "$(tmux -L "$RY_TMUX_SOCKET" display -p -t ym '#{pane_id}')"
  end_turn "$ID"
  run ry-watch.sh --once
  [ "$status" -eq 0 ]
  for _ in $(seq 1 30); do grep -q "$ID" "$out" 2>/dev/null && break; sleep 0.1; done
  grep -q "engine $ID turn-ended" "$out"
}

@test "watch survives a dead pane and still writes the inbox" {
  hold_yard tmux %999
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

# --- severed vs. merely slow --------------------------------------------
# A stalled engine whose siding still registers the Stop hook is probably
# just thinking. One whose siding does not register it (or never did) is
# permanently disconnected (issue #5) and cannot ever report on its own; the
# yardmaster needs a different line to tell the two apart.

@test "stall line stays 'silent for Nm' when the siding still registers the Stop hook" {
  echo running > "$RY_HOME/state/$ID.status"
  touch -t 202001010000 "$RY_HOME/state/$ID.status"
  siding="$RY_HOME/yard/xyz/$ID"
  mkdir -p "$siding/.claude"
  jq -n --arg cmd "exec $BATS_TEST_DIRNAME/../bin/ry-engine-stop.sh" \
    '{hooks:{Stop:[{hooks:[{type:"command",command:$cmd}]}]}}' \
    > "$siding/.claude/settings.local.json"
  RY_STALL_MIN=5 run ry-watch.sh --once
  [ "$status" -eq 0 ]
  grep -q "engine $ID silent for [0-9]*m (status running, no turn end); check window ry-$ID" "$RY_HOME/state/inbox.md"
}

@test "stall line names a severed engine when the siding has no Stop hook registration" {
  echo running > "$RY_HOME/state/$ID.status"
  touch -t 202001010000 "$RY_HOME/state/$ID.status"
  siding="$RY_HOME/yard/xyz/$ID"
  # No .claude/settings.local.json at all: the state a --resume relaunch
  # leaves behind before this fix, since the hook lived only in --settings.
  RY_STALL_MIN=5 run ry-watch.sh --once
  [ "$status" -eq 0 ]
  grep -q "not reporting" "$RY_HOME/state/inbox.md"
  grep -qF "$siding" "$RY_HOME/state/inbox.md"
  ! grep -q "silent for" "$RY_HOME/state/inbox.md"
  [ "$(grep -c "$ID" "$RY_HOME/state/inbox.md")" -eq 1 ]
}

@test "a Stop hook that does not name ry-engine-stop.sh also counts as not registered" {
  echo running > "$RY_HOME/state/$ID.status"
  touch -t 202001010000 "$RY_HOME/state/$ID.status"
  siding="$RY_HOME/yard/xyz/$ID"
  mkdir -p "$siding/.claude"
  jq -n '{hooks:{Stop:[{hooks:[{type:"command",command:"exec /some/other/hook.sh"}]}]}}' \
    > "$siding/.claude/settings.local.json"
  RY_STALL_MIN=5 run ry-watch.sh --once
  [ "$status" -eq 0 ]
  grep -q "not reporting" "$RY_HOME/state/inbox.md"
}

@test "the severed-engine line fires only once per engine" {
  echo running > "$RY_HOME/state/$ID.status"
  touch -t 202001010000 "$RY_HOME/state/$ID.status"
  RY_STALL_MIN=5 run ry-watch.sh --once
  RY_STALL_MIN=5 run ry-watch.sh --once
  [ "$(grep -c "not reporting" "$RY_HOME/state/inbox.md")" -eq 1 ]
}
