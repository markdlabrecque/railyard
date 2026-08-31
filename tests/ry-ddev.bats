#!/usr/bin/env bats
# Every siding of a DDEV project gets its own DDEV project name, written at
# couple time and torn down at decouple.
load helpers

setup() { setup_home; setup_ddev; make_project xyz; }

lib() { . "$BATS_TEST_DIRNAME/../bin/ry-lib.sh"; }

# --- prefix ------------------------------------------------------------------

@test "--prefix is recorded in the task's meta" {
  id=$(ry-dispatch.sh --haul --prefix 308 xyz "x" | sed -n 's/^id=//p')
  grep -q '^prefix=308$' "$RY_HOME/state/$id.meta"
}

@test "a bad --prefix is refused at dispatch time, naming the value" {
  for bad in "two words" "-lead" "has_underscore" "" ; do
    run ry-dispatch.sh --haul --prefix "$bad" xyz "x"
    [ "$status" -ne 0 ] || { echo "accepted '$bad'"; false; }
    [[ "$output" == *"--prefix"* ]]
  done
  [ -z "$(ls "$RY_HOME/state")" ]
}

@test "a bad --prefix is refused before any track is laid" {
  run ry-dispatch.sh --haul --prefix "no good" xyz "x"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no good"* ]]
  [ -z "$(ls "$RY_HOME/yard")" ]
}

@test "ry_prefix_valid accepts a ticket number and a single word" {
  lib
  run ry_prefix_valid 308;      [ "$status" -eq 0 ]
  run ry_prefix_valid ddev-fix; [ "$status" -eq 0 ]
  run ry_prefix_valid A1;       [ "$status" -eq 0 ]
  run ry_prefix_valid "a b";    [ "$status" -ne 0 ]
  run ry_prefix_valid "-a";     [ "$status" -ne 0 ]
  run ry_prefix_valid "a.b";    [ "$status" -ne 0 ]
}

@test "without --prefix the task id's random suffix is used" {
  id=$(ry-dispatch.sh --haul xyz "x" | sed -n 's/^id=//p')
  grep -q "^prefix=${id##*-}\$" "$RY_HOME/state/$id.meta"
}

# --- the name ----------------------------------------------------------------

@test "ry_ddev_name joins prefix and project" {
  lib
  run ry_ddev_name 3a8d island-health
  [ "$status" -eq 0 ]
  [ "$output" = "3a8d-island-health" ]
}

# Truncating to 63 would map two prefixes that differ only past the limit onto
# one DDEV project name -- the exact collision this change exists to prevent.
@test "ry_ddev_name refuses a name over 63 characters rather than truncating" {
  lib
  run ry_ddev_name "$(printf 'p%.0s' $(seq 1 61))" x   # 61 + 1 + 1 = 63
  [ "$status" -eq 0 ]
  [ "${#output}" -eq 63 ]
  run ry_ddev_name "$(printf 'p%.0s' $(seq 1 62))" x   # one over
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "an over-long --prefix is refused at dispatch, not truncated" {
  long=$(printf 'p%.0s' $(seq 1 80))
  run ry-dispatch.sh --haul --prefix "$long" xyz "x"
  [ "$status" -ne 0 ]
  [[ "$output" == *"--prefix"* ]]
  [[ "$output" == *"63"* ]]
  [ -z "$(ls "$RY_HOME/state")" ]
  [ -z "$(ls "$RY_HOME/yard")" ]
}

# The longest prefix that still fits must be accepted: the guard is a limit,
# not a excuse to refuse legitimate names.
@test "the longest prefix that fits is accepted end to end" {
  make_ddev_project xyz
  fits=$(printf 'p%.0s' $(seq 1 59))   # 59 + 1 + len("xyz") = 63
  id=$(ry-dispatch.sh --haul --prefix "$fits" xyz "x" | sed -n 's/^id=//p')
  grep -q "^name: $fits-xyz\$" "$RY_HOME/yard/xyz/$id/.ddev/config.local.yaml"
}

# --- couple ------------------------------------------------------------------

@test "couple writes the override with <prefix>-<project>" {
  make_ddev_project xyz
  id=$(ry-dispatch.sh --haul --prefix 308 xyz "x" | sed -n 's/^id=//p')
  f="$RY_HOME/yard/xyz/$id/.ddev/config.local.yaml"
  [ -f "$f" ]
  grep -q '^name: 308-xyz$' "$f"
  # and it does not dirty the siding
  [ -z "$(git -C "$RY_HOME/yard/xyz/$id" status --porcelain)" ]
}

@test "couple falls back to the id suffix when no prefix was given" {
  make_ddev_project xyz
  id=$(ry-dispatch.sh --haul xyz "x" | sed -n 's/^id=//p')
  grep -q "^name: ${id##*-}-xyz\$" "$RY_HOME/yard/xyz/$id/.ddev/config.local.yaml"
}

@test "a project without .ddev/ is untouched" {
  id=$(ry-dispatch.sh --haul xyz "x" | sed -n 's/^id=//p')
  [ ! -e "$RY_HOME/yard/xyz/$id/.ddev" ]
  [ -z "$(git -C "$RY_HOME/yard/xyz/$id" status --porcelain)" ]
}

@test "a project that tracks config.local.yaml fails loudly and writes nothing" {
  make_ddev_project xyz --tracked
  # the project really does track it: the failure path under test is "tracked",
  # not merely "no ignore rule"
  git -C "$RY_HOME/projects/xyz" ls-files --error-unmatch .ddev/config.local.yaml
  run ry-dispatch.sh --haul xyz "x"
  [ "$status" -ne 0 ]
  [[ "$output" == *"gitignore"* ]]
  [[ "$output" == *"xyz"* ]]
  [ -z "$(ls "$RY_HOME/yard/xyz" 2>/dev/null)" ]
}

@test "a failed override write is reported, not swallowed as success" {
  [ "$(id -u)" -ne 0 ] || skip "root ignores the read-only directory"
  lib
  make_ddev_project xyz
  siding="$BATS_TEST_TMPDIR/probe-siding"
  git -C "$RY_HOME/projects/xyz" worktree add -q -b probe "$siding" origin/main
  chmod a-w "$siding/.ddev"
  run ry_ddev_write_override "$siding" xyz 308
  chmod u+w "$siding/.ddev"
  [ "$status" -ne 0 ]
  [ ! -f "$siding/.ddev/config.local.yaml" ]
}

# --- decouple ----------------------------------------------------------------

@test "decouple deletes the siding's DDEV project before the worktree goes" {
  make_ddev_project xyz
  id=$(ry-dispatch.sh --haul --prefix 308 xyz "x" | sed -n 's/^id=//p')
  run ry-decouple.sh "$id"
  [ "$status" -eq 0 ]
  grep -q -- '308-xyz' "$RY_FAKE_DDEV_LOG"
  [ ! -e "$RY_HOME/yard/xyz/$id" ]
}

# The real `ddev delete` prompts and waits on stdin; the fake refuses a delete
# without --yes for that reason. Drop the flag and this test goes red.
@test "the delete is non-interactive: --yes is passed" {
  make_ddev_project xyz
  id=$(ry-dispatch.sh --haul --prefix 308 xyz "x" | sed -n 's/^id=//p')
  run ry-decouple.sh "$id"
  [ "$status" -eq 0 ]
  grep -qE -- '(--yes|(^| )-[A-Za-z]*y)' "$RY_FAKE_DDEV_LOG"
  # and the fake really would have caught its absence
  run "$BATS_TEST_DIRNAME/fakebin/ddev" delete --omit-snapshot 308-xyz
  [ "$status" -ne 0 ]
  [[ "$output" == *"prompt"* ]] || [[ "$output" == *"hang"* ]]
  run "$BATS_TEST_DIRNAME/fakebin/ddev" delete -Oy 308-xyz
  [ "$status" -eq 0 ]
}

@test "a siding with .ddev/ but no override still decouples" {
  make_ddev_project xyz
  id=$(ry-dispatch.sh --haul xyz "x" | sed -n 's/^id=//p')
  rm -f "$RY_HOME/yard/xyz/$id/.ddev/config.local.yaml"   # cut before this change
  run ry-decouple.sh "$id"
  [ "$status" -eq 0 ]
  [ ! -e "$RY_HOME/yard/xyz/$id" ]
  [ ! -s "$RY_FAKE_DDEV_LOG" ]
}

@test "decouple runs no ddev for a project without .ddev/" {
  id=$(ry-dispatch.sh --haul xyz "x" | sed -n 's/^id=//p')
  run ry-decouple.sh "$id"
  [ "$status" -eq 0 ]
  [ ! -s "$RY_FAKE_DDEV_LOG" ]
}

@test "a failing ddev does not block the decouple" {
  make_ddev_project xyz
  id=$(ry-dispatch.sh --haul xyz "x" | sed -n 's/^id=//p')
  RY_FAKE_DDEV_FAIL=1 run ry-decouple.sh "$id"
  [ "$status" -eq 0 ]
  [ ! -e "$RY_HOME/yard/xyz/$id" ]
  [ ! -f "$RY_HOME/state/$id.meta" ]
}

@test "a missing ddev binary does not block the decouple" {
  make_ddev_project xyz
  id=$(ry-dispatch.sh --haul xyz "x" | sed -n 's/^id=//p')
  PATH="$BATS_TEST_DIRNAME/../bin:/usr/bin:/bin" run ry-decouple.sh "$id"
  [ "$status" -eq 0 ]
  [ ! -e "$RY_HOME/yard/xyz/$id" ]
}
