#!/usr/bin/env bats
load helpers

setup() {
  setup_home; make_project xyz
  ID=$(ry-dispatch.sh --haul xyz "task" | sed -n 's/^id=//p')
  SIDING="$RY_HOME/yard/xyz/$ID"
}

@test "decouple removes siding, keeps branch, archives state" {
  run ry-decouple.sh "$ID"
  [ "$status" -eq 0 ]
  [ ! -e "$SIDING" ]
  git -C "$RY_HOME/projects/xyz" rev-parse --verify -q "ry/$ID" >/dev/null
  [ ! -e "$RY_HOME/state/$ID.meta" ]
  [ -f "$RY_HOME/state/archive/$ID/meta" ]
  [ "$(cat "$RY_HOME/state/archive/$ID/status")" = "decoupled" ]
  ! git -C "$RY_HOME/projects/xyz" worktree list | grep -q "$SIDING"
}

@test "decouple --delete-branch also drops the branch" {
  run ry-decouple.sh --delete-branch "$ID"
  [ "$status" -eq 0 ]
  ! git -C "$RY_HOME/projects/xyz" rev-parse --verify -q "ry/$ID" >/dev/null
}

@test "decouple refuses a dirty siding unless --force" {
  echo junk > "$SIDING/junk.txt"
  run ry-decouple.sh "$ID"
  [ "$status" -ne 0 ]
  [ -e "$SIDING" ]
  run ry-decouple.sh --force "$ID"
  [ "$status" -eq 0 ]
  [ ! -e "$SIDING" ]
}

@test "decouple refuses unknown id" {
  run ry-decouple.sh nope
  [ "$status" -ne 0 ]
}
