#!/usr/bin/env bats
load helpers

setup() { setup_home; make_project xyz; }

@test "dispatch haul creates siding on ry/<id> branch off default branch" {
  run ry-dispatch.sh --haul --mode local-only xyz "fix the login test"
  [ "$status" -eq 0 ]
  id=$(sed -n 's/^id=//p' <<<"$output")
  [ -n "$id" ]
  siding="$RY_HOME/yard/xyz/$id"
  [ -d "$siding/.git" ] || [ -f "$siding/.git" ]
  [ "$(git -C "$siding" rev-parse --abbrev-ref HEAD)" = "ry/$id" ]
  [ "$(git -C "$siding" rev-parse HEAD)" = "$(git -C "$RY_HOME/projects/xyz" rev-parse origin/main)" ]
}

@test "dispatch writes meta, status and waybill" {
  run ry-dispatch.sh --haul --mode pr xyz "add dark mode"
  [ "$status" -eq 0 ]
  id=$(sed -n 's/^id=//p' <<<"$output")
  grep -q '^shape=haul$'   "$RY_HOME/state/$id.meta"
  grep -q '^mode=pr$'      "$RY_HOME/state/$id.meta"
  grep -q '^project=xyz$'  "$RY_HOME/state/$id.meta"
  grep -q "^siding=$RY_HOME/yard/xyz/$id$" "$RY_HOME/state/$id.meta"
  [ "$(cat "$RY_HOME/state/$id.status")" = "dispatched" ]
  [ "$(cat "$RY_HOME/state/$id.waybill.md")" = "add dark mode" ]
}

@test "survey defaults to mode none and haul defaults to local-only" {
  run ry-dispatch.sh --survey xyz "why is CI slow"
  [ "$status" -eq 0 ]
  id=$(sed -n 's/^id=//p' <<<"$output")
  grep -q '^shape=survey$' "$RY_HOME/state/$id.meta"
  grep -q '^mode=none$'    "$RY_HOME/state/$id.meta"
  run ry-dispatch.sh --haul xyz "x"
  id=$(sed -n 's/^id=//p' <<<"$output")
  grep -q '^mode=local-only$' "$RY_HOME/state/$id.meta"
}

@test "dispatch refuses unknown project, bad mode, and missing shape" {
  run ry-dispatch.sh --haul nope "x";            [ "$status" -ne 0 ]
  run ry-dispatch.sh --haul --mode yolo xyz "x"; [ "$status" -ne 0 ]
  run ry-dispatch.sh xyz "x";                    [ "$status" -ne 0 ]
  [ -z "$(ls "$RY_HOME/state")" ]
}

@test "two dispatches get distinct ids" {
  a=$(ry-dispatch.sh --haul xyz "a" | sed -n 's/^id=//p')
  b=$(ry-dispatch.sh --haul xyz "b" | sed -n 's/^id=//p')
  [ "$a" != "$b" ]
}
