#!/usr/bin/env bats
load helpers
setup() { setup_home; make_project xyz; }

well_formed_block() {
  cat <<'EOF'
DONE: something changed

## Inspection
- inspector: ran
- suite: bats tests/ — 231 passed, 0 failed
- must-fix: 2 raised, 1 fixed, 1 rejected (byte-identical suggestion)
- revert check: tests/ry-foo.bats:42 — asserts the banner text, fails on a reverted copy
- risk: low — docs only
EOF
}

@test "prints usage for -h and --help" {
  run ry-verdict.sh -h
  [ "$status" -eq 0 ]
  [[ "$output" == *usage:* ]]
  run ry-verdict.sh --help
  [ "$status" -eq 0 ]
  [[ "$output" == *usage:* ]]
}

@test "a well-formed inspection block prints every field and exits 0" {
  A=$(ry-dispatch.sh --haul xyz "fix login" | sed -n 's/^id=//p')
  well_formed_block > "$RY_HOME/state/$A.last.md"
  run ry-verdict.sh "$A"
  [ "$status" -eq 0 ]
  [[ "$output" == *"## Inspection"* ]]
  [[ "$output" == *"- inspector: ran"* ]]
  [[ "$output" == *"- suite: bats tests/ — 231 passed, 0 failed"* ]]
  [[ "$output" == *"- must-fix: 2 raised, 1 fixed, 1 rejected (byte-identical suggestion)"* ]]
  [[ "$output" == *"- revert check: tests/ry-foo.bats:42 — asserts the banner text, fails on a reverted copy"* ]]
  [[ "$output" == *"- risk: low — docs only"* ]]
}

@test "the block stops at the next heading and does not print what follows" {
  A=$(ry-dispatch.sh --haul xyz "fix login" | sed -n 's/^id=//p')
  { well_formed_block; printf '\n## Notes\nsecret follow-up text\n'; } > "$RY_HOME/state/$A.last.md"
  run ry-verdict.sh "$A"
  [ "$status" -eq 0 ]
  [[ "$output" != *"secret follow-up text"* ]]
  [[ "$output" != *"## Notes"* ]]
}

@test "an unknown id is rejected" {
  run ry-verdict.sh nope-not-a-task
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown id"* ]]
}

@test "a known id with no handoff at all is rejected by name" {
  A=$(ry-dispatch.sh --haul xyz "fix login" | sed -n 's/^id=//p')
  run ry-verdict.sh "$A"
  [ "$status" -eq 2 ]
  [[ "$output" == *"$A.last.md"* ]]
}

@test "a handoff with no inspection block at all is rejected" {
  A=$(ry-dispatch.sh --haul xyz "fix login" | sed -n 's/^id=//p')
  echo "DONE: nothing to see here" > "$RY_HOME/state/$A.last.md"
  run ry-verdict.sh "$A"
  [ "$status" -eq 2 ]
  [[ "$output" == *Inspection* ]]
}

@test "a missing required field is named in the error" {
  A=$(ry-dispatch.sh --haul xyz "fix login" | sed -n 's/^id=//p')
  well_formed_block | grep -v '^- revert check:' > "$RY_HOME/state/$A.last.md"
  run ry-verdict.sh "$A"
  [ "$status" -eq 3 ]
  [[ "$output" == *"revert check"* ]]
}

@test "an unrecognized risk level is rejected" {
  A=$(ry-dispatch.sh --haul xyz "fix login" | sed -n 's/^id=//p')
  well_formed_block | sed 's/^- risk:.*/- risk: unclear/' > "$RY_HOME/state/$A.last.md"
  run ry-verdict.sh "$A"
  [ "$status" -eq 3 ]
  [[ "$output" == *"risk"* ]]
}

@test "inspector not run with no reason is rejected" {
  A=$(ry-dispatch.sh --haul xyz "fix login" | sed -n 's/^id=//p')
  well_formed_block | sed 's/^- inspector:.*/- inspector: not run/' > "$RY_HOME/state/$A.last.md"
  run ry-verdict.sh "$A"
  [ "$status" -eq 3 ]
  [[ "$output" == *"inspector"* ]]
}

@test "inspector not run with a parenthesised reason is accepted" {
  A=$(ry-dispatch.sh --haul xyz "fix login" | sed -n 's/^id=//p')
  well_formed_block | sed 's/^- inspector:.*/- inspector: not run (doc-only haul, 6 lines)/' > "$RY_HOME/state/$A.last.md"
  run ry-verdict.sh "$A"
  [ "$status" -eq 0 ]
  [[ "$output" == *"- inspector: not run (doc-only haul, 6 lines)"* ]]
}

@test "a survey task carries no inspection block by design and is accepted" {
  A=$(ry-dispatch.sh --survey xyz "why slow" | sed -n 's/^id=//p')
  echo "DONE: it is the db" > "$RY_HOME/state/$A.last.md"
  run ry-verdict.sh "$A"
  [ "$status" -eq 0 ]
  [[ "$output" == *survey* ]]
  [[ "$output" == *"no"*"block"* ]]
}

@test "an empty field value is rejected" {
  A=$(ry-dispatch.sh --haul xyz "fix login" | sed -n 's/^id=//p')
  well_formed_block | sed 's/^- suite:.*/- suite:/' > "$RY_HOME/state/$A.last.md"
  run ry-verdict.sh "$A"
  [ "$status" -eq 3 ]
  [[ "$output" == *"suite"* ]]
}
