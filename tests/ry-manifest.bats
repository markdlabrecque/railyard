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
  [ "$status" -eq 0 ]; [[ "$output" == *"no engines"* ]]
  A=$(ry-dispatch.sh --haul --mode pr xyz "t" | sed -n 's/^id=//p')
  echo pr-open > "$RY_HOME/state/$A.status"; printf 'forge=gitlab\npr_url=https://g/x/-/merge_requests/3\n' >> "$RY_HOME/state/$A.meta"
  printf 'a\nb\n' > "$RY_HOME/state/inbox.md"
  run ry-manifest.sh
  [[ "$output" == *"PR-OPEN"* ]]
  [[ "$output" == *"https://g/x/-/merge_requests/3"* ]]
  [[ "$output" == *"inbox: 2 unread"* ]]
}
