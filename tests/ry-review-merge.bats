#!/usr/bin/env bats
load helpers

setup() {
  setup_home; make_project xyz
  ID=$(ry-dispatch.sh --haul xyz "task" | sed -n 's/^id=//p')
  SIDING="$RY_HOME/yard/xyz/$ID"; PDIR="$RY_HOME/projects/xyz"
  git -C "$SIDING" config user.email e@e; git -C "$SIDING" config user.name e
  git -C "$PDIR" config user.email e@e; git -C "$PDIR" config user.name e
}
engine_commit() { echo "$1" > "$SIDING/$1.txt"; git -C "$SIDING" add -A; git -C "$SIDING" commit -qm "add $1"; }

@test "review shows header, commits and diff for the siding" {
  engine_commit feature
  run ry-review-diff.sh "$ID"
  [ "$status" -eq 0 ]
  [[ "$output" == *"id: $ID"* ]]
  [[ "$output" == *"mode: local-only"* ]]
  [[ "$output" == *"commits: 1"* ]]
  [[ "$output" == *"add feature"* ]]
  [[ "$output" == *"+feature"* ]]
  run ry-review-diff.sh --stat "$ID"
  [[ "$output" == *"feature.txt"* ]]
  [[ "$output" != *"+feature"* ]]
}

@test "review warns about uncommitted work in the siding" {
  echo junk > "$SIDING/junk.txt"
  run ry-review-diff.sh "$ID"
  [ "$status" -eq 0 ]
  [[ "$output" == *"UNCOMMITTED"* ]]
}

@test "merge-local fast-forwards the project default branch and marks merged" {
  engine_commit feature
  run ry-merge-local.sh "$ID"
  [ "$status" -eq 0 ]
  [ -f "$PDIR/feature.txt" ]
  [ "$(git -C "$PDIR" rev-parse main)" = "$(git -C "$SIDING" rev-parse HEAD)" ]
  [ "$(cat "$RY_HOME/state/$ID.status")" = "merged" ]
  # not pushed without --push
  [ "$(git -C "$PDIR" rev-parse origin/main)" != "$(git -C "$PDIR" rev-parse main)" ]
}

@test "merge-local --push also pushes" {
  engine_commit feature
  run ry-merge-local.sh --push "$ID"
  [ "$status" -eq 0 ]
  git -C "$PDIR" fetch -q
  [ "$(git -C "$PDIR" rev-parse origin/main)" = "$(git -C "$SIDING" rev-parse HEAD)" ]
}

@test "merge-local refuses: wrong mode, dirty siding, no commits" {
  PR=$(ry-dispatch.sh --haul --mode pr xyz "t" | sed -n 's/^id=//p')
  run ry-merge-local.sh "$PR";  [ "$status" -ne 0 ]; [[ "$output" == *"mode"* ]]
  run ry-merge-local.sh "$ID";  [ "$status" -ne 0 ]; [[ "$output" == *"no commits"* ]]
  echo junk > "$SIDING/junk.txt"; engine_commit feature; echo more > "$SIDING/junk.txt"
  run ry-merge-local.sh "$ID";  [ "$status" -ne 0 ]; [[ "$output" == *"uncommitted"* ]]
  [ "$(cat "$RY_HOME/state/$ID.status")" != "merged" ]
}

@test "merge-local refuses when origin moved ahead (not a fast-forward)" {
  engine_commit feature
  other="$BATS_TEST_TMPDIR/other"; git clone -q "$(git -C "$PDIR" remote get-url origin)" "$other"
  ( cd "$other" && git config user.email e@e && git config user.name e && echo x > x.txt && git add . && git commit -qm x && git push -q )
  run ry-merge-local.sh "$ID"
  [ "$status" -ne 0 ]; [[ "$output" == *"fast-forward"* ]]
  [ ! -f "$PDIR/feature.txt" ]
}
