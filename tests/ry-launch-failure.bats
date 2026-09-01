#!/usr/bin/env bats
# GitHub issue #22: Orca's `terminal create --worktree path:<siding>` can miss
# a just-created siding until Orca's own worktree index catches up, answering
# selector_not_found even though the siding is real. ry_orca_open must retry
# that specific race (3 attempts max, refreshing the index between them, on a
# configurable sleep), and a launch that never recovers must roll dispatch (or
# couple) back completely rather than leaving a half-cut task around.
load helpers

setup() { setup_home; setup_orca; make_project xyz; }
teardown() {
  pid=$(cat "$RY_HOME/state/.watch.lock" 2>/dev/null)
  [ -n "$pid" ] && kill "$pid" 2>/dev/null || true
}

lib() { . "$BATS_TEST_DIRNAME/../bin/ry-lib.sh"; . "$BATS_TEST_DIRNAME/../bin/ry-orca-lib.sh"; }

# --- ry_orca_open retry, unit level -----------------------------------------

@test "ry_orca_open retries terminal create on selector_not_found and succeeds on attempt 2" {
  export RY_FAKE_ORCA_CREATE_FAILS=1
  siding="$RY_HOME/yard/xyz/retry-2"
  mkdir -p "$siding"
  run bash -c "
    . '$BATS_TEST_DIRNAME/../bin/ry-lib.sh'
    . '$BATS_TEST_DIRNAME/../bin/ry-orca-lib.sh'
    ry_orca_open ry-retry-2 '$siding' true
  "
  [ "$status" -eq 0 ]
  [[ "$output" == term_fake_* ]]
  [ "$(grep -c -- 'terminal create' "$RY_FAKE_ORCA_LOG")" -eq 2 ]
  # the index is re-probed between attempts, not just blindly retried
  [ "$(grep -c -- 'worktree list' "$RY_FAKE_ORCA_LOG")" -ge 1 ]
}

@test "ry_orca_open gives up after exactly 3 terminal create attempts" {
  export RY_FAKE_ORCA_CREATE_FAILS=99
  siding="$RY_HOME/yard/xyz/retry-fail"
  mkdir -p "$siding"
  run bash -c "
    . '$BATS_TEST_DIRNAME/../bin/ry-lib.sh'
    . '$BATS_TEST_DIRNAME/../bin/ry-orca-lib.sh'
    ry_orca_open ry-retry-fail '$siding' true
  "
  [ "$status" -ne 0 ]
  # not 2, not 4: the cap is a cap
  [ "$(grep -c -- 'terminal create' "$RY_FAKE_ORCA_LOG")" -eq 3 ]
}

@test "ry_orca_open does not retry a non-selector_not_found error" {
  export RY_FAKE_ORCA_CREATE_ERROR=boom
  siding="$RY_HOME/yard/xyz/no-retry"
  mkdir -p "$siding"
  run bash -c "
    . '$BATS_TEST_DIRNAME/../bin/ry-lib.sh'
    . '$BATS_TEST_DIRNAME/../bin/ry-orca-lib.sh'
    ry_orca_open ry-no-retry '$siding' true
  "
  [ "$status" -ne 0 ]
  [ "$(grep -c -- 'terminal create' "$RY_FAKE_ORCA_LOG")" -eq 1 ]
}

@test "RY_ORCA_RETRY_SLEEP overrides the retry sleep (0 is fast, unset is a real sleep)" {
  export RY_FAKE_ORCA_CREATE_FAILS=1
  siding="$RY_HOME/yard/xyz/timing"
  mkdir -p "$siding"

  start=$(date +%s)
  RY_ORCA_RETRY_SLEEP=0 bash -c "
    . '$BATS_TEST_DIRNAME/../bin/ry-lib.sh'
    . '$BATS_TEST_DIRNAME/../bin/ry-orca-lib.sh'
    ry_orca_open ry-timing-fast '$siding' true
  " >/dev/null
  fast=$(( $(date +%s) - start ))
  [ "$fast" -lt 1 ]

  rm -f "$RY_FAKE_ORCA_CREATE_COUNTER"
  start=$(date +%s)
  env -u RY_ORCA_RETRY_SLEEP bash -c "
    . '$BATS_TEST_DIRNAME/../bin/ry-lib.sh'
    . '$BATS_TEST_DIRNAME/../bin/ry-orca-lib.sh'
    ry_orca_open ry-timing-slow '$siding' true
  " >/dev/null
  slow=$(( $(date +%s) - start ))
  [ "$slow" -ge 1 ]
}

# --- happy path through dispatch (point 2) ----------------------------------

@test "orca dispatch survives one selector_not_found and succeeds on attempt 2" {
  export RY_FAKE_ORCA_CREATE_FAILS=1
  run ry-dispatch.sh --haul xyz "fix it"
  [ "$status" -eq 0 ]
  id=$(sed -n 's/^id=//p' <<<"$output")
  [ -n "$id" ]
  grep -q '^backend=orca$' "$RY_HOME/state/$id.meta"
  grep -q '^target=term_fake_' "$RY_HOME/state/$id.meta"
  [ "$(cat "$RY_HOME/state/$id.status")" = "running" ]
  [ "$(grep -c -- 'terminal create' "$RY_FAKE_ORCA_LOG")" -gt 1 ]
}

# --- exhausted retries: dispatch rolls all the way back (point 3, revised) --

@test "orca dispatch: all 3 terminal create attempts fail -> dispatch fails and rolls everything back" {
  export RY_FAKE_ORCA_CREATE_FAILS=99
  run ry-dispatch.sh --haul xyz "fix it"
  [ "$status" -ne 0 ]
  id=$(sed -n 's/^id=//p' <<<"$output")
  [ -n "$id" ]

  [ ! -d "$RY_HOME/yard/xyz/$id" ]
  ! git -C "$RY_HOME/projects/xyz" worktree list | grep -q "$RY_HOME/yard/xyz/$id"
  ! git -C "$RY_HOME/projects/xyz" branch --list "ry/$id" | grep -q "ry/$id"

  [ ! -f "$RY_HOME/state/$id.meta" ]
  [ ! -f "$RY_HOME/state/$id.status" ]
  [ ! -f "$RY_HOME/state/$id.waybill.md" ]

  # loud, not silent success
  echo "$output" | grep -qi 'fail'
  [[ "$output" != *"status=running"* ]]

  [ "$(grep -c -- 'terminal create' "$RY_FAKE_ORCA_LOG")" -eq 3 ]

  grep -q "$id" "$RY_HOME/state/events.log"
  grep -q "launch-failed" "$RY_HOME/state/events.log"
}

@test "orca dispatch: a non-retryable error also rolls everything back, with only 1 attempt" {
  export RY_FAKE_ORCA_CREATE_ERROR=boom
  run ry-dispatch.sh --haul xyz "fix it"
  [ "$status" -ne 0 ]
  id=$(sed -n 's/^id=//p' <<<"$output")
  [ -n "$id" ]

  [ "$(grep -c -- 'terminal create' "$RY_FAKE_ORCA_LOG")" -eq 1 ]

  [ ! -d "$RY_HOME/yard/xyz/$id" ]
  ! git -C "$RY_HOME/projects/xyz" branch --list "ry/$id" | grep -q "ry/$id"
  [ ! -f "$RY_HOME/state/$id.meta" ]
  [ ! -f "$RY_HOME/state/$id.status" ]
  [ ! -f "$RY_HOME/state/$id.waybill.md" ]
}

# --- a queued task coupled separately: rolls its worktree back but keeps ----
# --- the task itself (point 5, revised) -------------------------------------

@test "couple: a queued task whose launch exhausts retries rolls back the worktree, stays queued, keeps its meta" {
  a=$(ry-dispatch.sh --haul xyz "a" | sed -n 's/^id=//p')
  b=$(ry-dispatch.sh --haul --after "$a" xyz "b" | sed -n 's/^id=//p')

  export RY_FAKE_ORCA_CREATE_FAILS=99
  run ry-couple.sh "$b"
  [ "$status" -ne 0 ]

  [ ! -d "$RY_HOME/yard/xyz/$b" ]
  ! git -C "$RY_HOME/projects/xyz" branch --list "ry/$b" | grep -q "ry/$b"

  [ "$(cat "$RY_HOME/state/$b.status")" = "queued" ]
  [ -f "$RY_HOME/state/$b.meta" ]
  [ -f "$RY_HOME/state/$b.waybill.md" ]
}

# --- another backend: same rollback contract, not orca-specific (point 7) --

@test "cmux dispatch: a launch failure rolls everything back too, not just orca's" {
  setup_cmux
  export RY_FAKE_CMUX_FAIL_OPEN=1
  run ry-dispatch.sh --haul xyz "fix it"
  [ "$status" -ne 0 ]
  id=$(sed -n 's/^id=//p' <<<"$output")
  [ -n "$id" ]

  [ ! -d "$RY_HOME/yard/xyz/$id" ]
  ! git -C "$RY_HOME/projects/xyz" branch --list "ry/$id" | grep -q "ry/$id"
  [ ! -f "$RY_HOME/state/$id.meta" ]
  [ ! -f "$RY_HOME/state/$id.status" ]
  [ ! -f "$RY_HOME/state/$id.waybill.md" ]

  grep -q "$id" "$RY_HOME/state/events.log"
  grep -q "launch-failed" "$RY_HOME/state/events.log"
}

@test "tmux dispatch: a launch failure rolls everything back too (';' would swallow it)" {
  export RY_BACKEND=tmux
  # Its own directory, not tests/fakebin/: setup_tmux puts tests/fakebin/ on
  # PATH ahead of real tmux too (for the fake claude binary), and every
  # other tmux test in the suite depends on that being the real tmux.
  export PATH="$BATS_TEST_DIRNAME/fakebin-tmux-fail:$PATH"
  export RY_FAKE_TMUX_FAIL_OPEN=1
  run ry-dispatch.sh --haul xyz "fix it"
  [ "$status" -ne 0 ]
  id=$(sed -n 's/^id=//p' <<<"$output")
  [ -n "$id" ]

  [ ! -d "$RY_HOME/yard/xyz/$id" ]
  ! git -C "$RY_HOME/projects/xyz" branch --list "ry/$id" | grep -q "ry/$id"
  [ ! -f "$RY_HOME/state/$id.meta" ]
  [ ! -f "$RY_HOME/state/$id.status" ]
  [ ! -f "$RY_HOME/state/$id.waybill.md" ]
  # a lying `target=` never made it into anything, because there is nothing left
  [[ "$output" != *"target=ry-"* ]]

  grep -q "$id" "$RY_HOME/state/events.log"
  grep -q "launch-failed" "$RY_HOME/state/events.log"
}

# --- a persistent failure must not feed the watcher's auto-couple loop -----

@test "watch does not re-couple a queued task once its launch has failed, and does not repeat the event" {
  a=$(ry-dispatch.sh --haul xyz "a" | sed -n 's/^id=//p')
  b=$(ry-dispatch.sh --haul --after "$a" xyz "b" | sed -n 's/^id=//p')
  echo merged > "$RY_HOME/state/$a.status"

  export RY_FAKE_ORCA_CREATE_FAILS=99
  run ry-watch.sh --once
  [ "$status" -eq 0 ]
  [ "$(cat "$RY_HOME/state/$b.status")" = queued ]
  [ -f "$RY_HOME/state/$b.launch-failed" ]
  [ "$(grep -c 'launch-failed' "$RY_HOME/state/events.log")" -eq 1 ]
  creates_1=$(grep -c -- 'terminal create' "$RY_FAKE_ORCA_LOG")

  # A second pass sees the same queued, ready task -- and the sentinel.
  run ry-watch.sh --once
  [ "$status" -eq 0 ]
  [ "$(cat "$RY_HOME/state/$b.status")" = queued ]
  [ -f "$RY_HOME/state/$b.launch-failed" ]
  [ -f "$RY_HOME/state/$b.meta" ]
  [ -f "$RY_HOME/state/$b.waybill.md" ]
  [ "$(grep -c 'launch-failed' "$RY_HOME/state/events.log")" -eq 1 ]
  [ "$(grep -c -- 'terminal create' "$RY_FAKE_ORCA_LOG")" -eq "$creates_1" ]

  # A deliberate manual retry clears the sentinel on entry and tries again --
  # it still fails (still FAILS=99), so the sentinel is written straight back.
  run ry-couple.sh "$b"
  [ "$status" -ne 0 ]
  [ -f "$RY_HOME/state/$b.launch-failed" ]
  [ "$(grep -c -- 'terminal create' "$RY_FAKE_ORCA_LOG")" -gt "$creates_1" ]
}
