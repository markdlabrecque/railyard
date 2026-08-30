#!/usr/bin/env bats
load helpers

setup() { setup_home; make_project xyz; }

@test "--after queues the task: no siding, no engine, status queued" {
  a=$(ry-dispatch.sh --haul xyz "first" | sed -n 's/^id=//p')
  run ry-dispatch.sh --haul --after "$a" xyz "second"
  [ "$status" -eq 0 ]
  b=$(sed -n 's/^id=//p' <<<"$output")
  [ "$(cat "$RY_HOME/state/$b.status")" = "queued" ]
  grep -q "^after=$a\$" "$RY_HOME/state/$b.meta"
  [ ! -d "$RY_HOME/yard/xyz/$b" ]
  [ "$(cat "$RY_HOME/state/$b.waybill.md")" = "second" ]
}

@test "--after records several blockers" {
  a=$(ry-dispatch.sh --haul xyz "a" | sed -n 's/^id=//p')
  b=$(ry-dispatch.sh --haul xyz "b" | sed -n 's/^id=//p')
  c=$(ry-dispatch.sh --haul --after "$a,$b" xyz "c" | sed -n 's/^id=//p')
  grep -q "^after=$a,$b\$" "$RY_HOME/state/$c.meta"
}

@test "--after refuses an unknown blocker and lays no track" {
  run ry-dispatch.sh --haul --after nosuchid xyz "x"
  [ "$status" -ne 0 ]
  [[ "$output" == *nosuchid* ]]
  [ -z "$(ls "$RY_HOME/yard")" ]
}

@test "couple cuts the siding and marks the task dispatched" {
  a=$(ry-dispatch.sh --haul xyz "a" | sed -n 's/^id=//p')
  b=$(ry-dispatch.sh --haul --after "$a" xyz "b" | sed -n 's/^id=//p')
  run ry-couple.sh "$b"
  [ "$status" -eq 0 ]
  siding="$RY_HOME/yard/xyz/$b"
  [ -d "$siding" ]
  [ "$(git -C "$siding" rev-parse --abbrev-ref HEAD)" = "ry/$b" ]
  [ "$(cat "$RY_HOME/state/$b.status")" = "dispatched" ]
}

@test "couple refuses a task that is not queued" {
  a=$(ry-dispatch.sh --haul xyz "a" | sed -n 's/^id=//p')
  run ry-couple.sh "$a"
  [ "$status" -ne 0 ]
}

@test "couple picks up a blocker merged locally but never pushed" {
  a=$(ry-dispatch.sh --haul xyz "a" | sed -n 's/^id=//p')
  b=$(ry-dispatch.sh --haul --after "$a" xyz "b" | sed -n 's/^id=//p')
  local_commit xyz "merged-but-unpushed"
  run ry-couple.sh "$b"
  [ "$status" -eq 0 ]
  [ -f "$RY_HOME/yard/xyz/$b/local.txt" ]
}

@test "couple uses origin when the clone's base is simply behind" {
  a=$(ry-dispatch.sh --haul xyz "a" | sed -n 's/^id=//p')
  b=$(ry-dispatch.sh --haul --after "$a" xyz "b" | sed -n 's/^id=//p')
  remote_commit xyz main "pushed-elsewhere"
  run ry-couple.sh "$b"
  [ "$status" -eq 0 ]
  [ -f "$RY_HOME/yard/xyz/$b/remote.txt" ]
}

@test "couple refuses when the clone's base has diverged from origin" {
  a=$(ry-dispatch.sh --haul xyz "a" | sed -n 's/^id=//p')
  b=$(ry-dispatch.sh --haul --after "$a" xyz "b" | sed -n 's/^id=//p')
  local_commit xyz "local-side"
  remote_commit xyz main "remote-side"
  run ry-couple.sh "$b"
  [ "$status" -ne 0 ]
  [[ "$output" == *diverged* ]]
  [ ! -d "$RY_HOME/yard/xyz/$b" ]
}

@test "decouple archives a queued task that never got a siding" {
  a=$(ry-dispatch.sh --haul xyz "a" | sed -n 's/^id=//p')
  b=$(ry-dispatch.sh --haul --after "$a" xyz "b" | sed -n 's/^id=//p')
  run ry-decouple.sh "$b"
  [ "$status" -eq 0 ]
  [ -f "$RY_HOME/state/archive/$b/status" ]
  [ ! -f "$RY_HOME/state/$b.meta" ]
}

@test "dispatch without --after still couples immediately" {
  id=$(ry-dispatch.sh --haul xyz "x" | sed -n 's/^id=//p')
  [ -d "$RY_HOME/yard/xyz/$id" ]
  [ "$(cat "$RY_HOME/state/$id.status")" = "dispatched" ]
}
