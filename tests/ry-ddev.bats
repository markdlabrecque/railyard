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

@test "ry_ddev_name caps at 63 characters and never ends in a dash" {
  lib
  run ry_ddev_name 3a8d island-health
  [ "$output" = "3a8d-island-health" ]
  long=$(printf 'p%.0s' $(seq 1 80))
  run ry_ddev_name "$long" island-health
  [ "${#output}" -eq 63 ]
  run ry_ddev_name "$(printf 'p%.0s' $(seq 1 62))" x
  [ "${#output}" -eq 62 ]      # the trailing dash left by the cut is dropped
  [[ "$output" != *- ]]
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
  run ry-dispatch.sh --haul xyz "x"
  [ "$status" -ne 0 ]
  [[ "$output" == *"gitignore"* ]]
  [[ "$output" == *"xyz"* ]]
  [ -z "$(ls "$RY_HOME/yard/xyz" 2>/dev/null)" ]
}

@test "the override is on disk before the engine is launched" {
  make_ddev_project xyz
  # ry-couple.sh reaches its sibling ry-engine-launch.sh by path, so the only
  # honest way to see the ordering is to run a copy of bin/ whose launcher is
  # a probe.
  probe="$BATS_TEST_TMPDIR/probebin"
  cp -R "$BATS_TEST_DIRNAME/../bin" "$probe"
  cat > "$probe/ry-engine-launch.sh" <<'PROBE'
#!/usr/bin/env bash
siding=$(sed -n 's/^siding=//p' "$RY_HOME/state/$1.meta")
if [ -f "$siding/.ddev/config.local.yaml" ]; then s=present; else s=absent; fi
printf '%s\n' "$s" > "$RY_HOME/launch-saw"
PROBE
  chmod +x "$probe/ry-engine-launch.sh"
  id=$(ry-dispatch.sh --haul --after "$(ry-dispatch.sh --haul xyz a | sed -n 's/^id=//p')" xyz "x" | sed -n 's/^id=//p')
  RY_BACKEND=tmux run "$probe/ry-couple.sh" "$id"
  [ "$status" -eq 0 ]
  [ "$(cat "$RY_HOME/launch-saw")" = present ]
}

# --- decouple ----------------------------------------------------------------

@test "decouple deletes the siding's DDEV project before the worktree goes" {
  make_ddev_project xyz
  id=$(ry-dispatch.sh --haul --prefix 308 xyz "x" | sed -n 's/^id=//p')
  run ry-decouple.sh "$id"
  [ "$status" -eq 0 ]
  grep -q -- 'ddev delete -O 308-xyz' "$RY_FAKE_DDEV_LOG"
  [ ! -e "$RY_HOME/yard/xyz/$id" ]
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
