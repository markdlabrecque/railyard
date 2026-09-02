#!/usr/bin/env bats
load helpers
setup() { setup_home; make_project xyz; }

# The manifest is a report, not program output (#37): markdown lists grouped by
# a lowercase status word, rows led by ticket and project, nothing over 80
# characters. These tests hold that shape.

longest_line() { awk '{ if (length > m) m = length } END { print m+0 }' <<<"$1"; }

@test "manifest lists tasks grouped by status with project, shape, mode, age and last line" {
  A=$(ry-dispatch.sh --haul xyz "fix login" | sed -n 's/^id=//p')
  B=$(ry-dispatch.sh --survey xyz "why slow" | sed -n 's/^id=//p')
  echo running > "$RY_HOME/state/$A.status"
  echo turn-ended > "$RY_HOME/state/$B.status"; echo "DONE: it is the db" > "$RY_HOME/state/$B.last.md"
  run ry-manifest.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\nrunning\n\n- xyz haul, local-only, 0m: '"$A"$'\n'* ]] ||
  [[ "$output" == $'running\n\n- xyz haul, local-only, 0m: '"$A"$'\n'* ]]
  [[ "$output" == *$'\nturn-ended\n\n- xyz survey, 0m: '"$B"$'\n  - DONE: it is the db\n'* ]]
  [[ "$output" == *"inbox: 0 unread"* ]]
}

@test "status headers are lowercase words, not shouted" {
  A=$(ry-dispatch.sh --haul xyz "fix login" | sed -n 's/^id=//p')
  echo running > "$RY_HOME/state/$A.status"
  run ry-manifest.sh
  [ "$status" -eq 0 ]
  [[ "$output" != *RUNNING* ]]
  ! grep -qE '^[A-Z][A-Z-]+$' <<<"$output"
}

@test "rows lead with the ticket, then the project; the task id never leads" {
  t=$(ry-dispatch.sh --haul --ticket 16 --slug "name work" xyz "wb" | sed -n 's/^id=//p')
  n=$(ry-dispatch.sh --haul --slug "news filter styling" xyz "wb" | sed -n 's/^id=//p')
  run ry-manifest.sh
  [ "$status" -eq 0 ]
  grep -qE "^- #16 xyz haul, local-only, [0-9]+m: $t\$" <<<"$output"
  grep -qE "^- xyz haul, local-only, [0-9]+m: $n\$" <<<"$output"
  ! grep -qE "^- *(#)?($t|$n)" <<<"$output"
  [[ "$output" != *"# $n"* ]]
}

@test "no output line exceeds 80 characters, however long the handoff line" {
  A=$(ry-dispatch.sh --haul --ticket 297 --slug "news filter no scroll jump" xyz "wb" | sed -n 's/^id=//p')
  echo turn-ended > "$RY_HOME/state/$A.status"
  long="DONE: recorded decision A as answered in docs/CURRENT.md, EDs become SAL pages, no automatic migration implied, the four open questions stay open, and the file now names who decided and when so a fresh session does not re-derive it from the thread history, which it did twice last week and once the week before"
  [ ${#long} -gt 300 ]
  printf '%s\n\n## Inspection\n- inspector: ran\n- risk: low — documentation only, no code or config touched\n' "$long" > "$RY_HOME/state/$A.last.md"
  run ry-manifest.sh
  [ "$status" -eq 0 ]
  [ "$(longest_line "$output")" -le 80 ]
  # the front of the sentence survives, the cut is marked, the risk line follows
  [[ "$output" == *"  - DONE: recorded decision A as answered in docs/CURRENT.md, EDs become SAL"* ]]
  grep -qE '^    .*…$' <<<"$output"
  [[ "$output" != *"once the week before"* ]]
  [[ "$output" == *$'\n  - risk: low — documentation only, no code or config touched\n'* ]]
}

@test "the handoff line gets two lines at most; a word wider than a line is split, not overflowed" {
  A=$(ry-dispatch.sh --haul xyz "wb" | sed -n 's/^id=//p')
  echo turn-ended > "$RY_HOME/state/$A.status"
  printf 'DONE: %s\n' "$(printf 'x%.0s' $(seq 200))" > "$RY_HOME/state/$A.last.md"
  run ry-manifest.sh
  [ "$status" -eq 0 ]
  [ "$(longest_line "$output")" -le 80 ]
  [ "$(grep -c 'xxxx' <<<"$output")" -eq 2 ]
  [[ "$output" == *"  - DONE: xxxx"* ]]
  grep -qE '^    x+…$' <<<"$output"
}

@test "indentation stops at two levels: a row and its sub-bullets" {
  a=$(ry-dispatch.sh --haul xyz "a" | sed -n 's/^id=//p')
  b=$(ry-dispatch.sh --haul --after "$a" xyz "b" | sed -n 's/^id=//p')
  echo turn-ended > "$RY_HOME/state/$a.status"
  printf 'DONE: %s\n\n## Inspection\n- risk: low — nothing\n' "$(printf 'word %.0s' $(seq 40))" > "$RY_HOME/state/$a.last.md"
  run ry-manifest.sh
  [ "$status" -eq 0 ]
  # every non-blank line is a header, a row, a sub-bullet, or a sub-bullet's own
  # wrapped continuation (aligned under its text, not a deeper level)
  ! grep -vE '^$|^[a-z-]+$|^inbox: |^- |^  - |^    [^ -]' <<<"$output"
}

@test "manifest shows pr url and unread inbox count, and is calm when empty" {
  run ry-manifest.sh
  [ "$status" -eq 0 ]; [ "$output" = $'no tasks\ninbox: 0 unread' ]
  A=$(ry-dispatch.sh --haul --mode pr xyz "t" | sed -n 's/^id=//p')
  echo pr-open > "$RY_HOME/state/$A.status"; printf 'forge=gitlab\npr_url=https://g/x/-/merge_requests/3\n' >> "$RY_HOME/state/$A.meta"
  printf 'a\nb\n' > "$RY_HOME/state/inbox.md"
  run ry-manifest.sh
  [[ "$output" == $'pr-open\n\n- xyz haul, pr, '* ]]
  [[ "$output" == *$'\n  - https://g/x/-/merge_requests/3\n'* ]]
  [[ "$output" == *"inbox: 2 unread"* ]]
}

@test "statuses come out in lifecycle order: queued before running before turn-ended" {
  a=$(ry-dispatch.sh --haul xyz "a" | sed -n 's/^id=//p')
  b=$(ry-dispatch.sh --haul xyz "b" | sed -n 's/^id=//p')
  c=$(ry-dispatch.sh --haul --after "$a" xyz "c" | sed -n 's/^id=//p')
  echo turn-ended > "$RY_HOME/state/$a.status"
  echo running > "$RY_HOME/state/$b.status"
  run ry-manifest.sh
  [ "$status" -eq 0 ]
  [ "$(grep -E '^[a-z-]+$' <<<"$output" | paste -sd' ')" = "queued running turn-ended" ]
}

@test "manifest lists queued tasks" {
  a=$(ry-dispatch.sh --haul xyz "a" | sed -n 's/^id=//p')
  b=$(ry-dispatch.sh --haul --after "$a" xyz "b" | sed -n 's/^id=//p')
  run ry-manifest.sh
  [ "$status" -eq 0 ]
  [[ "$output" == $'queued\n\n'* ]]
  [[ "$output" == *": $b"* ]]
}

@test "a queued row names what it is waiting on" {
  a=$(ry-dispatch.sh --haul xyz "a" | sed -n 's/^id=//p')
  b=$(ry-dispatch.sh --haul --after "$a" xyz "b" | sed -n 's/^id=//p')
  echo running > "$RY_HOME/state/$a.status"
  run ry-manifest.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *": $b"$'\n  - waiting on '"$a"$'\n'* ]]
}

@test "a stranded row says so and names the decision" {
  a=$(ry-dispatch.sh --haul xyz "a" | sed -n 's/^id=//p')
  b=$(ry-dispatch.sh --haul --after "$a" xyz "b" | sed -n 's/^id=//p')
  echo turn-ended > "$RY_HOME/state/$a.status"
  ry-decouple.sh --force "$a"
  run ry-manifest.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *": $b"$'\n  - **stranded**: '"$a was dropped without merging."* ]]
  [[ "$(tr -s ' \n' ' ' <<<"$output")" == *"Drop this task or release the block."* ]]
  [ "$(longest_line "$output")" -le 80 ]
}

@test "an empty manifest speaks of tasks, not engines" {
  run ry-manifest.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"no tasks"* ]]
}

@test "a finished task's row also shows the inspection's risk line" {
  A=$(ry-dispatch.sh --haul xyz "fix login" | sed -n 's/^id=//p')
  echo turn-ended > "$RY_HOME/state/$A.status"
  printf 'DONE: fixed it\n\n## Inspection\n- inspector: ran\n- suite: bats tests/ — 5 passed, 0 failed\n- must-fix: 0 raised\n- revert check: tests/ry-foo.bats:1\n- risk: medium — touches auth\n' > "$RY_HOME/state/$A.last.md"
  run ry-manifest.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\n  - DONE: fixed it\n  - risk: medium — touches auth\n'* ]]
}

@test "the board's risk line comes from the inspection block, not from prose" {
  A=$(ry-dispatch.sh --haul xyz "fix login" | sed -n 's/^id=//p')
  echo turn-ended > "$RY_HOME/state/$A.status"
  printf 'DONE: fixed it\n\n## Notes\n- risk: high — quoted from the waybill, not a verdict\n\n## Inspection\n- inspector: ran\n- risk: low — one line changed\n' > "$RY_HOME/state/$A.last.md"
  run ry-manifest.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"  - risk: low — one line changed"* ]]
  [[ "$output" != *"quoted from the waybill"* ]]
}
