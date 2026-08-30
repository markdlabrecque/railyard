#!/usr/bin/env bats
load helpers

setup() { setup_home; make_project xyz; }

@test "base falls back to develop when the project has one and says nothing" {
  make_branch xyz develop
  run ry-dispatch.sh --haul xyz "x"
  [ "$status" -eq 0 ]
  id=$(sed -n 's/^id=//p' <<<"$output")
  grep -q '^base=develop$' "$RY_HOME/state/$id.meta"
}

@test "base falls back to the default branch when there is no develop" {
  run ry-dispatch.sh --haul xyz "x"
  [ "$status" -eq 0 ]
  id=$(sed -n 's/^id=//p' <<<"$output")
  grep -q '^base=main$' "$RY_HOME/state/$id.meta"
}

@test "projects.md base wins over the develop default" {
  make_branch xyz develop
  make_branch xyz staging
  register_project xyz pr staging
  run ry-dispatch.sh --haul xyz "x"
  [ "$status" -eq 0 ]
  id=$(sed -n 's/^id=//p' <<<"$output")
  grep -q '^base=staging$' "$RY_HOME/state/$id.meta"
}

@test "--base wins over projects.md and over develop" {
  make_branch xyz develop
  make_branch xyz staging
  register_project xyz pr staging
  run ry-dispatch.sh --haul --base develop xyz "x"
  [ "$status" -eq 0 ]
  id=$(sed -n 's/^id=//p' <<<"$output")
  grep -q '^base=develop$' "$RY_HOME/state/$id.meta"
}

@test "a projects.md line without a base does not disturb the develop default" {
  make_branch xyz develop
  register_project xyz pr
  run ry-dispatch.sh --haul xyz "x"
  [ "$status" -eq 0 ]
  id=$(sed -n 's/^id=//p' <<<"$output")
  grep -q '^base=develop$' "$RY_HOME/state/$id.meta"
}

@test "only the matching project's line is read" {
  make_branch xyz develop
  make_branch xyz staging
  register_project other pr staging
  register_project xyz pr
  run ry-dispatch.sh --haul xyz "x"
  [ "$status" -eq 0 ]
  id=$(sed -n 's/^id=//p' <<<"$output")
  grep -q '^base=develop$' "$RY_HOME/state/$id.meta"
}

@test "dispatch refuses a base branch that does not exist on origin, laying no track" {
  run ry-dispatch.sh --haul --base nope xyz "x"
  [ "$status" -ne 0 ]
  [[ "$output" == *nope* ]]
  [ -z "$(ls "$RY_HOME/state")" ]
  [ -z "$(ls "$RY_HOME/yard")" ]
}

@test "the siding is cut from the resolved base, not the default branch" {
  make_branch xyz develop
  ( cd "$RY_HOME/projects/xyz" && git checkout -q -b develop origin/develop &&
    echo more >> README.md && git commit -qam "develop only" && git push -q origin develop )
  run ry-dispatch.sh --haul xyz "x"
  [ "$status" -eq 0 ]
  id=$(sed -n 's/^id=//p' <<<"$output")
  siding="$RY_HOME/yard/xyz/$id"
  [ "$(git -C "$siding" rev-parse HEAD)" = "$(git -C "$RY_HOME/projects/xyz" rev-parse origin/develop)" ]
  [ "$(git -C "$siding" rev-parse HEAD)" != "$(git -C "$RY_HOME/projects/xyz" rev-parse origin/main)" ]
}

@test "dispatch reports the resolved base" {
  make_branch xyz develop
  run ry-dispatch.sh --haul xyz "x"
  [ "$status" -eq 0 ]
  [[ "$output" == *"base=develop"* ]]
}
