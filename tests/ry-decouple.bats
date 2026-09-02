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

# data/<id>/ goes with the task (#34): empty is removed, files move to
# data/<project>/<id>-<file>, and nothing else under data/ is touched.

@test "haul dispatch creates no data/<id>/" {
  [ ! -e "$RY_HOME/data/$ID" ]
}

@test "decouple removes an empty data/<id>/ and leaves other dirs alone" {
  mkdir -p "$RY_HOME/data/$ID" "$RY_HOME/data/railway"
  echo parked > "$RY_HOME/data/railway/notes.md"
  run ry-decouple.sh "$ID"
  [ "$status" -eq 0 ]
  [ ! -e "$RY_HOME/data/$ID" ]
  [ ! -e "$RY_HOME/data/xyz" ]
  [ "$(cat "$RY_HOME/data/railway/notes.md")" = parked ]
}

@test "decouple moves a report to data/<project>/<id>-report.md" {
  mkdir -p "$RY_HOME/data/$ID"
  printf 'findings\n' > "$RY_HOME/data/$ID/report.md"
  run ry-decouple.sh --force --delete-branch "$ID"
  [ "$status" -eq 0 ]
  [ ! -e "$RY_HOME/data/$ID" ]
  [ "$(find "$RY_HOME/data/xyz" -type f | wc -l)" -eq 1 ]
  [ "$(cat "$RY_HOME/data/xyz/$ID-report.md")" = findings ]
}

@test "two surveys of one project keep both reports" {
  ID2=$(ry-dispatch.sh --haul xyz "task" | sed -n 's/^id=//p')
  [ "$ID2" != "$ID" ]
  mkdir -p "$RY_HOME/data/$ID" "$RY_HOME/data/$ID2"
  echo one > "$RY_HOME/data/$ID/report.md"
  echo two > "$RY_HOME/data/$ID2/report.md"
  ry-decouple.sh "$ID"; ry-decouple.sh "$ID2"
  [ "$(cat "$RY_HOME/data/xyz/$ID-report.md")" = one ]
  [ "$(cat "$RY_HOME/data/xyz/$ID2-report.md")" = two ]
}

@test "decouple keeps every file, drops only .DS_Store" {
  mkdir -p "$RY_HOME/data/$ID/sub"
  echo body > "$RY_HOME/data/$ID/pr-body.md"
  echo deep > "$RY_HOME/data/$ID/sub/notes.md"
  : > "$RY_HOME/data/$ID/.DS_Store"
  run ry-decouple.sh "$ID"
  [ "$status" -eq 0 ]
  [ ! -e "$RY_HOME/data/$ID" ]
  [ "$(cat "$RY_HOME/data/xyz/$ID-pr-body.md")" = body ]
  [ "$(cat "$RY_HOME/data/xyz/$ID-sub-notes.md")" = deep ]
  [ "$(find "$RY_HOME/data/xyz" -type f | wc -l)" -eq 2 ]
}

@test "decouple of a dir holding only .DS_Store adds nothing to data/<project>/" {
  mkdir -p "$RY_HOME/data/$ID"; : > "$RY_HOME/data/$ID/.DS_Store"
  run ry-decouple.sh "$ID"
  [ "$status" -eq 0 ]
  [ ! -e "$RY_HOME/data/$ID" ]
  [ ! -e "$RY_HOME/data/xyz" ]
}
