#!/usr/bin/env bats
load helpers

setup() {
  setup_home; make_project xyz
  A=$(ry-dispatch.sh --haul xyz "blocker" | sed -n 's/^id=//p')
  B=$(ry-dispatch.sh --haul --after "$A" xyz "waiter" | sed -n 's/^id=//p')
}

@test "watch couples a queued task once its blocker has merged" {
  echo merged > "$RY_HOME/state/$A.status"
  run ry-watch.sh --once
  [ "$status" -eq 0 ]
  [ -d "$RY_HOME/yard/xyz/$B" ]
  [ "$(cat "$RY_HOME/state/$B.status")" = "dispatched" ]
  grep -q "engine $B coupled" "$RY_HOME/state/inbox.md"
}

@test "watch leaves a queued task alone while its blocker is in flight" {
  echo running > "$RY_HOME/state/$A.status"
  run ry-watch.sh --once
  [ "$status" -eq 0 ]
  [ ! -d "$RY_HOME/yard/xyz/$B" ]
  [ "$(cat "$RY_HOME/state/$B.status")" = "queued" ]
  [ ! -s "$RY_HOME/state/inbox.md" ]
}

@test "watch couples a queued task only once" {
  echo merged > "$RY_HOME/state/$A.status"
  ry-watch.sh --once
  ry-watch.sh --once
  [ "$(grep -c "engine $B coupled" "$RY_HOME/state/inbox.md")" -eq 1 ]
}

@test "watch warns once about a stranded task and does not couple it" {
  echo turn-ended > "$RY_HOME/state/$A.status"
  ry-decouple.sh --force "$A"
  run ry-watch.sh --once
  [ "$status" -eq 0 ]
  [ ! -d "$RY_HOME/yard/xyz/$B" ]
  [ "$(cat "$RY_HOME/state/$B.status")" = "queued" ]
  grep -q "engine $B blocked-stranded" "$RY_HOME/state/inbox.md"
  ry-watch.sh --once
  [ "$(grep -c "engine $B blocked-stranded" "$RY_HOME/state/inbox.md")" -eq 1 ]
}

@test "a queued task is never flagged as stalled" {
  echo running > "$RY_HOME/state/$A.status"
  touch -t 200001010000 "$RY_HOME/state/$B.status"
  run ry-watch.sh --once
  [ "$status" -eq 0 ]
  ! grep -q "silent for" "$RY_HOME/state/inbox.md"
}

@test "watch couples a whole chain as each blocker merges" {
  C=$(ry-dispatch.sh --haul --after "$B" xyz "last" | sed -n 's/^id=//p')
  echo merged > "$RY_HOME/state/$A.status"
  ry-watch.sh --once
  [ "$(cat "$RY_HOME/state/$B.status")" = "dispatched" ]
  [ "$(cat "$RY_HOME/state/$C.status")" = "queued" ]
  echo merged > "$RY_HOME/state/$B.status"
  ry-watch.sh --once
  [ "$(cat "$RY_HOME/state/$C.status")" = "dispatched" ]
  [ -d "$RY_HOME/yard/xyz/$C" ]
}
