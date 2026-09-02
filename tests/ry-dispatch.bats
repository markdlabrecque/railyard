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

# no-mistakes was accepted by dispatch and implemented by nothing downstream:
# ry-merge-local.sh takes only local-only and ry-pr.sh only pr, so the mode
# could be dispatched and then never delivered. It is refused until it means
# something.
@test "no-mistakes is refused, and its refusal names the modes that work" {
  run ry-dispatch.sh --haul --mode no-mistakes xyz "x"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no-mistakes"* ]]
  [[ "$output" == *"local-only"* ]]
  [[ "$output" == *"pr"* ]]
  [ -z "$(ls "$RY_HOME/state")" ]
}

@test "two dispatches get distinct ids" {
  a=$(ry-dispatch.sh --haul xyz "a" | sed -n 's/^id=//p')
  b=$(ry-dispatch.sh --haul xyz "b" | sed -n 's/^id=//p')
  [ "$a" != "$b" ]
}

# The waybill's first line is the PR/MR title. Refused here, at the one moment
# it is cheap to fix, rather than by the forge after ry-pr.sh has pushed.
@test "a waybill whose first line is over the cap is refused, and cuts no siding" {
  long="A really long prose first line of the kind every waybill on disk opened with before this rule existed."
  [ "${#long}" -gt 80 ]
  run ry-dispatch.sh --haul --mode pr xyz "$long"
  [ "$status" -ne 0 ]
  [[ "$output" == *"80"* ]]
  [[ "$output" == *"${#long}"* ]]
  # nothing written, nothing cut, no branch left behind
  [ -z "$(ls "$RY_HOME/state")" ]
  [ -z "$(ls -A "$RY_HOME/yard")" ]
  [ -z "$(git -C "$RY_HOME/projects/xyz" for-each-ref --format='%(refname)' 'refs/heads/ry/*')" ]
}

@test "the cap is on the first line only: line 1 at exactly 80 is fine, 81 is not" {
  at80=$(printf 'b%.0s' $(seq 1 80))
  id=$(ry-dispatch.sh --haul xyz "$at80

A body of prose as long as it likes, well past eighty characters, on line three." \
    | sed -n 's/^id=//p')
  [ -n "$id" ]
  [ "$(head -n1 "$RY_HOME/state/$id.waybill.md")" = "$at80" ]
  run ry-dispatch.sh --haul xyz "$(printf 'c%.0s' $(seq 1 81))"
  [ "$status" -ne 0 ]
}

@test "surveys are held to the same cap as hauls" {
  run ry-dispatch.sh --survey xyz "$(printf 'd%.0s' $(seq 1 81))"
  [ "$status" -ne 0 ]
  [ -z "$(ls "$RY_HOME/state")" ]
}

@test "a blank first line is refused too: the title is not optional" {
  run ry-dispatch.sh --haul xyz "

The body starts here, and line 1 is where the title should have been."
  [ "$status" -ne 0 ]
  [[ "$output" == *"blank"* ]]
  [ -z "$(ls "$RY_HOME/state")" ]
  run ry-dispatch.sh --haul xyz "   "
  [ "$status" -ne 0 ]
  [ -z "$(ls "$RY_HOME/state")" ]
}

# The cap lives in three places: RY_TITLE_MAX, and the two documents that bind
# the people who have to obey it. Changing the number in one of them is AC7
# rotting behind a green suite, so the suite reads all three.
@test "the waybill title rule is stated where it binds, with the same cap" {
  cap=$(bash -c ". '$BATS_TEST_DIRNAME/../bin/ry-lib.sh'; printf %s \"\$RY_TITLE_MAX\"")
  [ "$cap" = 80 ]
  for f in "$BATS_TEST_DIRNAME/../AGENTS.md" \
           "$BATS_TEST_DIRNAME/../templates/engine-preamble.md"; do
    grep -qi 'first line' "$f" || { echo "$f does not mention the first line"; false; }
    grep -qi 'title' "$f"      || { echo "$f does not call it a title"; false; }
    grep -q "$cap characters" "$f" \
      || { echo "$f does not state the cap as $cap characters"; false; }
    grep -q 'line 3' "$f" || { echo "$f does not say the body starts on line 3"; false; }
  done
}
