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

@test "a heading with a trailing space is still the inspection block" {
  A=$(ry-dispatch.sh --haul xyz "fix login" | sed -n 's/^id=//p')
  well_formed_block | sed 's/^## Inspection$/## Inspection /' > "$RY_HOME/state/$A.last.md"
  run ry-verdict.sh "$A"
  [ "$status" -eq 0 ]
  [[ "$output" == *"- risk: low — docs only"* ]]
}

@test "a CRLF handoff parses" {
  A=$(ry-dispatch.sh --haul xyz "fix login" | sed -n 's/^id=//p')
  well_formed_block | sed 's/$/\r/' > "$RY_HOME/state/$A.last.md"
  run ry-verdict.sh "$A"
  [ "$status" -eq 0 ]
  [[ "$output" == *"- inspector: ran"* ]]
}

@test "the block stops at a fence, so a copied template does not leak" {
  # An engine that copies the preamble's fenced example emits a closing fence
  # right after the risk line. It is not part of the verdict.
  A=$(ry-dispatch.sh --haul xyz "fix login" | sed -n 's/^id=//p')
  { well_formed_block; printf '```\nprose after the fence\n'; } > "$RY_HOME/state/$A.last.md"
  run ry-verdict.sh "$A"
  [ "$status" -eq 0 ]
  [[ "$output" != *"prose after the fence"* ]]
  [[ "$output" != *'```'* ]]
}

@test "the block stops at a subheading too" {
  A=$(ry-dispatch.sh --haul xyz "fix login" | sed -n 's/^id=//p')
  { well_formed_block; printf '\n### Notes\nburied detail\n'; } > "$RY_HOME/state/$A.last.md"
  run ry-verdict.sh "$A"
  [ "$status" -eq 0 ]
  [[ "$output" != *"buried detail"* ]]
}

@test "a risk grade must be a whole word, not a prefix" {
  A=$(ry-dispatch.sh --haul xyz "fix login" | sed -n 's/^id=//p')
  well_formed_block | sed 's/^- risk:.*/- risk: lowkey unsure/' > "$RY_HOME/state/$A.last.md"
  run ry-verdict.sh "$A"
  [ "$status" -eq 3 ]
  [[ "$output" == *"risk"* ]]
}

@test "a suite line with no counts says nothing and is rejected" {
  A=$(ry-dispatch.sh --haul xyz "fix login" | sed -n 's/^id=//p')
  well_formed_block | sed 's/^- suite:.*/- suite: not run/' > "$RY_HOME/state/$A.last.md"
  run ry-verdict.sh "$A"
  [ "$status" -eq 3 ]
  [[ "$output" == *"suite"* ]]
}

@test "a must-fix line with no counts is rejected" {
  A=$(ry-dispatch.sh --haul xyz "fix login" | sed -n 's/^id=//p')
  well_formed_block | sed 's/^- must-fix:.*/- must-fix: all clean/' > "$RY_HOME/state/$A.last.md"
  run ry-verdict.sh "$A"
  [ "$status" -eq 3 ]
  [[ "$output" == *"must-fix"* ]]
}

@test "a revert check naming no file and line is rejected" {
  A=$(ry-dispatch.sh --haul xyz "fix login" | sed -n 's/^id=//p')
  well_formed_block | sed 's/^- revert check:.*/- revert check: skipped/' > "$RY_HOME/state/$A.last.md"
  run ry-verdict.sh "$A"
  [ "$status" -eq 3 ]
  [[ "$output" == *"revert check"* ]]
}

@test "a revert check of not applicable with a reason is accepted" {
  A=$(ry-dispatch.sh --haul xyz "fix login" | sed -n 's/^id=//p')
  well_formed_block | sed 's|^- revert check:.*|- revert check: not applicable — the change is a generated file with no assertion of its own|' > "$RY_HOME/state/$A.last.md"
  run ry-verdict.sh "$A"
  [ "$status" -eq 0 ]
  [[ "$output" == *"not applicable"* ]]
}

@test "a bare not applicable with no reason is rejected" {
  A=$(ry-dispatch.sh --haul xyz "fix login" | sed -n 's/^id=//p')
  well_formed_block | sed 's/^- revert check:.*/- revert check: not applicable/' > "$RY_HOME/state/$A.last.md"
  run ry-verdict.sh "$A"
  [ "$status" -eq 3 ]
  [[ "$output" == *"revert check"* ]]
}

@test "a digit somewhere is not a suite result" {
  A=$(ry-dispatch.sh --haul xyz "fix login" | sed -n 's/^id=//p')
  well_formed_block | sed 's/^- suite:.*/- suite: reviewed issue #13/' > "$RY_HOME/state/$A.last.md"
  run ry-verdict.sh "$A"
  [ "$status" -eq 3 ]
  [[ "$output" == *"suite"* ]]
}

@test "a suite result must carry both counts, not just the passes" {
  A=$(ry-dispatch.sh --haul xyz "fix login" | sed -n 's/^id=//p')
  well_formed_block | sed 's|^- suite:.*|- suite: bats tests/ — 300 passed|' > "$RY_HOME/state/$A.last.md"
  run ry-verdict.sh "$A"
  [ "$status" -eq 3 ]
  [[ "$output" == *"suite"* ]]
}

@test "a digit somewhere is not a must-fix count" {
  A=$(ry-dispatch.sh --haul xyz "fix login" | sed -n 's/^id=//p')
  well_formed_block | sed 's/^- must-fix:.*/- must-fix: see PR #23/' > "$RY_HOME/state/$A.last.md"
  run ry-verdict.sh "$A"
  [ "$status" -eq 3 ]
  [[ "$output" == *"must-fix"* ]]
}

# --- the skip is checked against the diff, not taken on trust ----------------

siding_commit() {  # <id> <path> — commit one file into the task's siding
  local siding; siding="$RY_HOME/yard/xyz/$1"
  git -C "$siding" config user.email e@e; git -C "$siding" config user.name e
  mkdir -p "$(dirname "$siding/$2")"; echo change > "$siding/$2"
  git -C "$siding" add -A; git -C "$siding" commit -qm "touch $2"
}

@test "a skipped inspector is accepted when the diff really is documentation only" {
  A=$(ry-dispatch.sh --haul xyz "tidy the readme" | sed -n 's/^id=//p')
  siding_commit "$A" docs/guide.md
  well_formed_block | sed 's/^- inspector:.*/- inspector: not run (doc-only haul, 6 lines)/' > "$RY_HOME/state/$A.last.md"
  run ry-verdict.sh "$A"
  [ "$status" -eq 0 ]
}

@test "a skipped inspector is rejected when the diff touches code" {
  A=$(ry-dispatch.sh --haul xyz "fix login" | sed -n 's/^id=//p')
  siding_commit "$A" bin/thing.sh
  well_formed_block | sed 's/^- inspector:.*/- inspector: not run (simple change)/' > "$RY_HOME/state/$A.last.md"
  run ry-verdict.sh "$A"
  [ "$status" -eq 3 ]
  [[ "$output" == *"inspector"* ]]
  [[ "$output" == *"bin/thing.sh"* ]]
}

@test "a skipped inspector is rejected when the diff touches tests" {
  A=$(ry-dispatch.sh --haul xyz "add coverage" | sed -n 's/^id=//p')
  siding_commit "$A" tests/ry-thing.bats
  well_formed_block | sed 's/^- inspector:.*/- inspector: not run (only a test)/' > "$RY_HOME/state/$A.last.md"
  run ry-verdict.sh "$A"
  [ "$status" -eq 3 ]
  [[ "$output" == *"tests/ry-thing.bats"* ]]
}

@test "a skipped inspector is rejected on a mixed diff, naming the code file" {
  A=$(ry-dispatch.sh --haul xyz "docs and code" | sed -n 's/^id=//p')
  siding_commit "$A" README.md
  siding_commit "$A" bin/other.sh
  well_formed_block | sed 's/^- inspector:.*/- inspector: not run (mostly docs)/' > "$RY_HOME/state/$A.last.md"
  run ry-verdict.sh "$A"
  [ "$status" -eq 3 ]
  [[ "$output" == *"bin/other.sh"* ]]
}

@test "an inspector that ran is not checked against the diff at all" {
  A=$(ry-dispatch.sh --haul xyz "fix login" | sed -n 's/^id=//p')
  siding_commit "$A" bin/thing.sh
  well_formed_block > "$RY_HOME/state/$A.last.md"
  run ry-verdict.sh "$A"
  [ "$status" -eq 0 ]
}

@test "a gone siding warns rather than failing a handoff it cannot check" {
  A=$(ry-dispatch.sh --haul xyz "fix login" | sed -n 's/^id=//p')
  well_formed_block | sed 's/^- inspector:.*/- inspector: not run (doc-only haul)/' > "$RY_HOME/state/$A.last.md"
  rm -rf "$RY_HOME/yard/xyz/$A"
  run ry-verdict.sh "$A"
  [ "$status" -eq 0 ]
  [[ "$output" == *"cannot be checked"* ]]
}

