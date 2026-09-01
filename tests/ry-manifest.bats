#!/usr/bin/env bats
load helpers
setup() { setup_home; make_project xyz; }

@test "manifest lists engines grouped by status with project, shape, mode, age and last line" {
  A=$(ry-dispatch.sh --haul xyz "fix login" | sed -n 's/^id=//p')
  B=$(ry-dispatch.sh --survey xyz "why slow" | sed -n 's/^id=//p')
  echo running > "$RY_HOME/state/$A.status"
  echo turn-ended > "$RY_HOME/state/$B.status"; echo "DONE: it is the db" > "$RY_HOME/state/$B.last.md"
  run ry-manifest.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"RUNNING"* ]]
  [[ "$output" == *"$A  xyz  haul  local-only"* ]]
  [[ "$output" == *"TURN-ENDED"* ]]
  [[ "$output" == *"$B  xyz  survey  none"* ]]
  [[ "$output" == *"DONE: it is the db"* ]]
  [[ "$output" == *"inbox: 0 unread"* ]]
}

@test "manifest shows pr url and unread inbox count, and is calm when empty" {
  run ry-manifest.sh
  [ "$status" -eq 0 ]; [[ "$output" == *"no tasks"* ]]
  A=$(ry-dispatch.sh --haul --mode pr xyz "t" | sed -n 's/^id=//p')
  echo pr-open > "$RY_HOME/state/$A.status"; printf 'forge=gitlab\npr_url=https://g/x/-/merge_requests/3\n' >> "$RY_HOME/state/$A.meta"
  printf 'a\nb\n' > "$RY_HOME/state/inbox.md"
  run ry-manifest.sh
  [[ "$output" == *"PR-OPEN"* ]]
  [[ "$output" == *"https://g/x/-/merge_requests/3"* ]]
  [[ "$output" == *"inbox: 2 unread"* ]]
}

@test "manifest lists queued tasks" {
  a=$(ry-dispatch.sh --haul xyz "a" | sed -n 's/^id=//p')
  b=$(ry-dispatch.sh --haul --after "$a" xyz "b" | sed -n 's/^id=//p')
  run ry-manifest.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *QUEUED* ]]
  [[ "$output" == *"$b"* ]]
}

@test "a queued row names what it is waiting on" {
  a=$(ry-dispatch.sh --haul xyz "a" | sed -n 's/^id=//p')
  b=$(ry-dispatch.sh --haul --after "$a" xyz "b" | sed -n 's/^id=//p')
  echo running > "$RY_HOME/state/$a.status"
  run ry-manifest.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *QUEUED* ]]
  [[ "$output" == *"waiting on $a"* ]]
}

@test "a stranded row says so and names the decision" {
  a=$(ry-dispatch.sh --haul xyz "a" | sed -n 's/^id=//p')
  b=$(ry-dispatch.sh --haul --after "$a" xyz "b" | sed -n 's/^id=//p')
  echo turn-ended > "$RY_HOME/state/$a.status"
  ry-decouple.sh --force "$a"
  run ry-manifest.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *STRANDED* ]]
  [[ "$output" == *"$a"* ]]
}

@test "an empty manifest speaks of tasks, not engines" {
  run ry-manifest.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"no tasks"* ]]
}

@test "a finished task's row also shows the inspection's risk line" {
  A=$(ry-dispatch.sh --haul xyz "fix login" | sed -n 's/^id=//p')
  echo turn-ended > "$RY_HOME/state/$A.status"
  printf 'DONE: fixed it\n\n## Inspection\n- inspector: ran\n- suite: bats tests/ — 5 passed, 0 failed\n- must-fix: 0 raised\n- revert check: tests/ry-foo.bats:1\n- risk: medium — touches auth\n' > "$RY_HOME/state/$A.last.md"
  run ry-manifest.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"DONE: fixed it"* ]]
  [[ "$output" == *"- risk: medium — touches auth"* ]]
}

@test "the board's risk line comes from the inspection block, not from prose" {
  A=$(ry-dispatch.sh --haul xyz "fix login" | sed -n 's/^id=//p')
  echo turn-ended > "$RY_HOME/state/$A.status"
  printf 'DONE: fixed it\n\n## Notes\n- risk: high — quoted from the waybill, not a verdict\n\n## Inspection\n- inspector: ran\n- risk: low — one line changed\n' > "$RY_HOME/state/$A.last.md"
  run ry-manifest.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"- risk: low — one line changed"* ]]
  [[ "$output" != *"quoted from the waybill"* ]]
}
