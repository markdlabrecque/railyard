#!/usr/bin/env bats
load helpers

setup() { setup_home; make_project xyz; }

@test "a task with no blockers is ready" {
  a=$(ry-dispatch.sh --haul xyz "a" | sed -n 's/^id=//p')
  run ry-deps.sh "$a"
  [ "$status" -eq 0 ]
  [[ "$output" == *"state=ready"* ]]
}

@test "a blocker still in flight leaves the task pending" {
  a=$(ry-dispatch.sh --haul xyz "a" | sed -n 's/^id=//p')
  b=$(ry-dispatch.sh --haul --after "$a" xyz "b" | sed -n 's/^id=//p')
  echo running > "$RY_HOME/state/$a.status"
  run ry-deps.sh "$b"
  [ "$status" -eq 0 ]
  [[ "$output" == *"state=pending"* ]]
  [[ "$output" == *"$a"* ]]
}

@test "a merged blocker makes the task ready" {
  a=$(ry-dispatch.sh --haul xyz "a" | sed -n 's/^id=//p')
  b=$(ry-dispatch.sh --haul --after "$a" xyz "b" | sed -n 's/^id=//p')
  echo merged > "$RY_HOME/state/$a.status"
  run ry-deps.sh "$b"
  [ "$status" -eq 0 ]
  [[ "$output" == *"state=ready"* ]]
}

@test "every blocker must be merged, not just one" {
  a=$(ry-dispatch.sh --haul xyz "a" | sed -n 's/^id=//p')
  b=$(ry-dispatch.sh --haul xyz "b" | sed -n 's/^id=//p')
  c=$(ry-dispatch.sh --haul --after "$a,$b" xyz "c" | sed -n 's/^id=//p')
  echo merged > "$RY_HOME/state/$a.status"
  echo running > "$RY_HOME/state/$b.status"
  run ry-deps.sh "$c"
  [[ "$output" == *"state=pending"* ]]
  echo merged > "$RY_HOME/state/$b.status"
  run ry-deps.sh "$c"
  [[ "$output" == *"state=ready"* ]]
}

@test "a blocker merged and then decoupled still counts as merged" {
  a=$(ry-dispatch.sh --haul xyz "a" | sed -n 's/^id=//p')
  b=$(ry-dispatch.sh --haul --after "$a" xyz "b" | sed -n 's/^id=//p')
  echo merged > "$RY_HOME/state/$a.status"
  ry-decouple.sh --force "$a"
  [ ! -f "$RY_HOME/state/$a.status" ]
  run ry-deps.sh "$b"
  [ "$status" -eq 0 ]
  [[ "$output" == *"state=ready"* ]]
}

@test "a blocker dropped without merging strands the task" {
  a=$(ry-dispatch.sh --haul xyz "a" | sed -n 's/^id=//p')
  b=$(ry-dispatch.sh --haul --after "$a" xyz "b" | sed -n 's/^id=//p')
  echo turn-ended > "$RY_HOME/state/$a.status"
  ry-decouple.sh --force "$a"
  run ry-deps.sh "$b"
  [ "$status" -eq 0 ]
  [[ "$output" == *"state=stranded"* ]]
  [[ "$output" == *"$a"* ]]
}

@test "decouple records the outcome it archived" {
  a=$(ry-dispatch.sh --haul xyz "a" | sed -n 's/^id=//p')
  echo merged > "$RY_HOME/state/$a.status"
  ry-decouple.sh --force "$a"
  grep -q '^outcome=merged$' "$RY_HOME/state/archive/$a/meta"
}

@test "dispatch refuses to queue behind an already stranded blocker" {
  a=$(ry-dispatch.sh --haul xyz "a" | sed -n 's/^id=//p')
  echo turn-ended > "$RY_HOME/state/$a.status"
  ry-decouple.sh --force "$a"
  run ry-dispatch.sh --haul --after "$a" xyz "b"
  [ "$status" -ne 0 ]
  [[ "$output" == *"$a"* ]]
}

@test "stranded beats pending when both are present" {
  a=$(ry-dispatch.sh --haul xyz "a" | sed -n 's/^id=//p')
  b=$(ry-dispatch.sh --haul xyz "b" | sed -n 's/^id=//p')
  c=$(ry-dispatch.sh --haul --after "$a,$b" xyz "c" | sed -n 's/^id=//p')
  echo running > "$RY_HOME/state/$a.status"
  echo turn-ended > "$RY_HOME/state/$b.status"
  ry-decouple.sh --force "$b"
  run ry-deps.sh "$c"
  [[ "$output" == *"state=stranded"* ]]
}
