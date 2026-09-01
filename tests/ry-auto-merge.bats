#!/usr/bin/env bats
# The auto-merge gate: bin/ry-auto-merge.sh arms auto-merge only once the
# forge's own view of the PR/MR shows a check exists for the head commit, is
# not blocked by conflicts, and has not already failed. Opt-in via
# auto_merge= in the task's meta (written by ry-pr.sh --auto-merge).
load helpers

setup() {
  setup_home; make_project xyz
  export PATH="$BATS_TEST_DIRNAME/fakebin:$PATH"
  export RY_FAKE_FORGE_LOG="$BATS_TEST_TMPDIR/forge.log"
  export RY_FAKE_GH_VIEW="$BATS_TEST_TMPDIR/gh.json" RY_FAKE_GLAB_VIEW="$BATS_TEST_TMPDIR/glab.json"
  export RY_FAKE_GLAB_API="$BATS_TEST_TMPDIR/glab-api.json"
  export RY_AUTO_MERGE_TRIES=3 RY_AUTO_MERGE_SLEEP=0
  ID=$(ry-dispatch.sh --haul --mode pr xyz "add dark mode" | sed -n 's/^id=//p')
  SIDING="$RY_HOME/yard/xyz/$ID"
  git -C "$SIDING" config user.email e@e; git -C "$SIDING" config user.name e
  echo x > "$SIDING/dark.css"; git -C "$SIDING" add -A; git -C "$SIDING" commit -qm "add dark mode css"
  EV="$RY_HOME/state/events.log"
}

# Open the PR/MR through the real ry-pr.sh, then opt it in to auto-merge by
# hand. This keeps these tests independent of the --auto-merge flag itself
# (covered separately in tests/ry-pr.bats), so a bug in the flag's parsing
# cannot mask a bug in the gate.
open_gh() {  # [method]
  RY_FORGE=github ry-pr.sh "$ID" >/dev/null
  printf 'auto_merge=%s\n' "${1:-merge}" >> "$RY_HOME/state/$ID.meta"
}
open_gl() {  # [method]
  RY_FORGE=gitlab ry-pr.sh "$ID" >/dev/null
  printf 'auto_merge=%s\n' "${1:-merge}" >> "$RY_HOME/state/$ID.meta"
}

gh_view() {  # <mergeStateStatus> <rollup-json-array-body>
  printf '{"state":"OPEN","headRefOid":"abc123","mergeStateStatus":"%s","statusCheckRollup":[%s]}\n' \
    "$1" "$2" > "$RY_FAKE_GH_VIEW"
}
gl_api() {  # <detailed_merge_status> <head_pipeline-json-or-null>
  printf '{"sha":"deadbeef","detailed_merge_status":"%s","head_pipeline":%s,"state":"opened"}\n' \
    "$1" "$2" > "$RY_FAKE_GLAB_API"
}

@test "usage for -h and --help" {
  run bash bin/ry-auto-merge.sh -h
  [ "$status" -eq 0 ]
  [[ "$output" == *usage:* ]]
}

@test "refuses with no id, no pr_url, no auto_merge" {
  run ry-auto-merge.sh
  [ "$status" -ne 0 ]

  L=$(ry-dispatch.sh --haul --mode pr xyz "no pr yet" | sed -n 's/^id=//p')
  run ry-auto-merge.sh "$L"
  [ "$status" -ne 0 ]

  RY_FORGE=gitlab ry-pr.sh "$ID" >/dev/null   # pr_url now set, but no auto_merge=
  run ry-auto-merge.sh "$ID"
  [ "$status" -ne 0 ]
}

@test "already-armed is a no-op success: no forge call at all" {
  open_gh
  : > "$RY_HOME/state/$ID.auto-armed"
  before=$(wc -l < "$RY_FAKE_FORGE_LOG")
  run ry-auto-merge.sh "$ID"
  [ "$status" -eq 0 ]
  after=$(wc -l < "$RY_FAKE_FORGE_LOG")
  [ "$before" -eq "$after" ]
}

# --- github ------------------------------------------------------------------

@test "github: head commit with no checks created -> waiting, no merge call, no arm" {
  open_gh
  gh_view CLEAN ""
  run ry-auto-merge.sh "$ID"
  [ "$status" -eq 0 ]
  [[ "$output" == *"auto-merge=waiting reason=no-checks"* ]]
  ! grep -q "pr merge" "$RY_FAKE_FORGE_LOG"
  [ ! -e "$RY_HOME/state/$ID.auto-armed" ]
  [ "$(grep -c "auto-merge-waiting" "$EV")" -eq 1 ]
  run ry-auto-merge.sh "$ID"
  [ "$(grep -c "auto-merge-waiting" "$EV")" -eq 1 ]
}

@test "github: one pending check -> armed with --auto, status untouched" {
  open_gh
  gh_view CLEAN '{"status":"IN_PROGRESS"}'
  run ry-auto-merge.sh "$ID"
  [ "$status" -eq 0 ]
  [[ "$output" == *"auto-merge=armed sha=abc123"* ]]
  grep -q -- "gh pr merge https://github.com/o/r/pull/7 --auto --merge --match-head-commit abc123" "$RY_FAKE_FORGE_LOG"
  [ -e "$RY_HOME/state/$ID.auto-armed" ]
  grep -q "auto-merge-armed https://github.com/o/r/pull/7 sha=abc123" "$EV"
  [ "$(cat "$RY_HOME/state/$ID.status")" = "pr-open" ]
}

@test "github: checks green and clean -> merge called without --auto" {
  open_gh
  gh_view CLEAN '{"status":"COMPLETED","conclusion":"SUCCESS"}'
  run ry-auto-merge.sh "$ID"
  [ "$status" -eq 0 ]
  grep -q -- "gh pr merge https://github.com/o/r/pull/7 --merge --match-head-commit abc123" "$RY_FAKE_FORGE_LOG"
  ! grep -- "gh pr merge" "$RY_FAKE_FORGE_LOG" | grep -q -- "--auto"
  [ -e "$RY_HOME/state/$ID.auto-armed" ]
}

@test "github: conflict -> blocked, no merge call, no arm" {
  open_gh
  gh_view DIRTY '{"status":"COMPLETED","conclusion":"SUCCESS"}'
  run ry-auto-merge.sh "$ID"
  [ "$status" -eq 0 ]
  [[ "$output" == *"auto-merge=blocked reason=conflict"* ]]
  ! grep -q "pr merge" "$RY_FAKE_FORGE_LOG"
  [ ! -e "$RY_HOME/state/$ID.auto-armed" ]
  grep -q "auto-merge-blocked https://github.com/o/r/pull/7 reason=conflict" "$EV"
}

@test "github: a failed check blocks, does not duplicate pr-checks-failed" {
  open_gh
  gh_view CLEAN '{"status":"COMPLETED","conclusion":"FAILURE"}'
  run ry-auto-merge.sh "$ID"
  [ "$status" -eq 0 ]
  [[ "$output" == *"auto-merge=blocked reason=checks-failed"* ]]
  ! grep -q "pr merge" "$RY_FAKE_FORGE_LOG"
  [ ! -e "$RY_HOME/state/$ID.auto-armed" ]
  grep -q "auto-merge-blocked https://github.com/o/r/pull/7 reason=checks-failed" "$EV"
  ! grep -q "pr-checks-failed" "$EV"
}

@test "github: merge failure that is not 405 reports unavailable, exits 0" {
  open_gh
  gh_view CLEAN '{"status":"COMPLETED","conclusion":"SUCCESS"}'
  echo "GraphQL: Pull Request is not mergeable: the base branch policy prohibits the merge." > "$BATS_TEST_TMPDIR/gh-merge-fail"
  RY_FAKE_GH_MERGE_FAIL="$BATS_TEST_TMPDIR/gh-merge-fail" run ry-auto-merge.sh "$ID"
  [ "$status" -eq 0 ]
  [[ "$output" == *"auto-merge=unavailable"* ]]
  [ ! -e "$RY_HOME/state/$ID.auto-armed" ]
  grep -q "auto-merge-blocked https://github.com/o/r/pull/7 reason=unavailable" "$EV"
}

# --- gitlab --------------------------------------------------------------------

@test "gitlab: no pipeline created -> waiting, no merge call, no arm" {
  open_gl
  gl_api mergeable null
  run ry-auto-merge.sh "$ID"
  [ "$status" -eq 0 ]
  [[ "$output" == *"auto-merge=waiting reason=no-checks"* ]]
  ! grep -q "mr merge" "$RY_FAKE_FORGE_LOG"
  [ ! -e "$RY_HOME/state/$ID.auto-armed" ]
}

@test "gitlab: pipeline sha differs from MR sha -> treated as no checks" {
  open_gl
  gl_api mergeable '{"sha":"stalepipeline","status":"success"}'
  run ry-auto-merge.sh "$ID"
  [ "$status" -eq 0 ]
  [[ "$output" == *"auto-merge=waiting reason=no-checks"* ]]
  ! grep -q "mr merge" "$RY_FAKE_FORGE_LOG"
}

@test "gitlab: conflict -> blocked, no merge call" {
  open_gl
  gl_api cannot_be_merged '{"sha":"deadbeef","status":"success"}'
  run ry-auto-merge.sh "$ID"
  [ "$status" -eq 0 ]
  [[ "$output" == *"auto-merge=blocked reason=conflict"* ]]
  ! grep -q "mr merge" "$RY_FAKE_FORGE_LOG"
  [ ! -e "$RY_HOME/state/$ID.auto-armed" ]
}

@test "gitlab: 405 while checking is retried to success" {
  open_gl
  # The settling loop's own polls: two 'checking' reads, then mergeable.
  printf '{"sha":"deadbeef","detailed_merge_status":"checking","head_pipeline":{"sha":"deadbeef","status":"running"},"state":"opened"}\n{"sha":"deadbeef","detailed_merge_status":"checking","head_pipeline":{"sha":"deadbeef","status":"running"},"state":"opened"}\n' \
    > "$BATS_TEST_TMPDIR/glab-api-seq"
  export RY_FAKE_GLAB_API_SEQ="$BATS_TEST_TMPDIR/glab-api-seq"
  gl_api mergeable '{"sha":"deadbeef","status":"running"}'   # steady state once settled
  printf '405 Method Not Allowed\n405 Method Not Allowed\n\n' > "$BATS_TEST_TMPDIR/glab-merge-fails"
  export RY_FAKE_GLAB_MERGE_FAILS="$BATS_TEST_TMPDIR/glab-merge-fails"
  run ry-auto-merge.sh "$ID"
  [ "$status" -eq 0 ]
  [[ "$output" == *"auto-merge=armed"* ]]
  [ -e "$RY_HOME/state/$ID.auto-armed" ]
  [ "$(grep -c "mr merge" "$RY_FAKE_FORGE_LOG")" -eq 3 ]
  [[ "$output" != *error* ]]
  [[ "$output" != *405* ]]
}

@test "gitlab: 405 forever exhausts the try budget -> waiting, not armed" {
  open_gl
  gl_api mergeable '{"sha":"deadbeef","status":"running"}'
  printf '405 Method Not Allowed\n405 Method Not Allowed\n405 Method Not Allowed\n' > "$BATS_TEST_TMPDIR/glab-merge-fails"
  export RY_FAKE_GLAB_MERGE_FAILS="$BATS_TEST_TMPDIR/glab-merge-fails"
  run ry-auto-merge.sh "$ID"
  [ "$status" -eq 0 ]
  [[ "$output" == *"auto-merge=waiting reason=checking"* ]]
  [ ! -e "$RY_HOME/state/$ID.auto-armed" ]
}

@test "every glab mr merge call carries --yes" {
  open_gl
  gl_api mergeable '{"sha":"deadbeef","status":"running"}'
  run ry-auto-merge.sh "$ID"
  [ "$status" -eq 0 ]
  n=$(grep -c "^glab mr merge" "$RY_FAKE_FORGE_LOG")
  [ "$n" -gt 0 ]
  [ "$(grep "^glab mr merge" "$RY_FAKE_FORGE_LOG" | grep -c -- "--yes")" -eq "$n" ]
}

@test "gitlab: running pipeline arms with --auto-merge and --sha" {
  open_gl
  gl_api mergeable '{"sha":"deadbeef","status":"running"}'
  run ry-auto-merge.sh "$ID"
  [ "$status" -eq 0 ]
  grep -q -- "glab mr merge 12 --yes --auto-merge --sha deadbeef" "$RY_FAKE_FORGE_LOG"
}

@test "gitlab: success pipeline arms without --auto-merge, still carries --sha" {
  open_gl
  gl_api mergeable '{"sha":"deadbeef","status":"success"}'
  run ry-auto-merge.sh "$ID"
  [ "$status" -eq 0 ]
  grep -q -- "glab mr merge 12 --yes --sha deadbeef" "$RY_FAKE_FORGE_LOG"
  ! grep -- "glab mr merge" "$RY_FAKE_FORGE_LOG" | grep -q -- "--auto-merge"
}

@test "already armed -> second invocation makes no merge call" {
  open_gl
  gl_api mergeable '{"sha":"deadbeef","status":"success"}'
  run ry-auto-merge.sh "$ID"
  [ "$status" -eq 0 ]
  n=$(grep -c "mr merge" "$RY_FAKE_FORGE_LOG")
  run ry-auto-merge.sh "$ID"
  [ "$status" -eq 0 ]
  [ "$(grep -c "mr merge" "$RY_FAKE_FORGE_LOG")" -eq "$n" ]
}

# --- #10 regression guard and the watcher's wiring ---------------------------

@test "#10 regression: an armed PR still reports pr-merged and couples the queue" {
  B=$(ry-dispatch.sh --haul --after "$ID" xyz "waiter" | sed -n 's/^id=//p')
  open_gl
  gl_api mergeable '{"sha":"deadbeef","status":"success"}'
  echo '{"state":"opened","head_pipeline":{"status":"running"}}' > "$RY_FAKE_GLAB_VIEW"
  RY_PR_POLL_SEC=0 ry-watch.sh --once
  [ -e "$RY_HOME/state/$ID.auto-armed" ]

  echo '{"state":"merged","head_pipeline":{"status":"success"}}' > "$RY_FAKE_GLAB_VIEW"
  RY_PR_POLL_SEC=0 ry-watch.sh --once
  [ "$(cat "$RY_HOME/state/$ID.status")" = "merged" ]
  grep -q "engine $ID pr-merged: https://gitlab.example.com/grp/sub/r/-/merge_requests/12" "$RY_HOME/state/inbox.md"

  RY_PR_POLL_SEC=0 ry-watch.sh --once
  [ "$(cat "$RY_HOME/state/$B.status")" = "dispatched" ]
  grep -q "engine $B coupled" "$RY_HOME/state/inbox.md"
}

@test "the watcher calls ry-auto-merge.sh only while unarmed" {
  open_gl
  gl_api mergeable '{"sha":"deadbeef","status":"success"}'
  echo '{"state":"opened","head_pipeline":{"status":"running"}}' > "$RY_FAKE_GLAB_VIEW"
  RY_PR_POLL_SEC=0 ry-watch.sh --once
  [ -e "$RY_HOME/state/$ID.auto-armed" ]
  n=$(grep -c "^glab api" "$RY_FAKE_FORGE_LOG")
  RY_PR_POLL_SEC=0 ry-watch.sh --once
  [ "$(grep -c "^glab api" "$RY_FAKE_FORGE_LOG")" -eq "$n" ]
}
