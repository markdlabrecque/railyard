#!/usr/bin/env bats
# A PR that goes green has to say so. These cover ry-pr-poll.sh's phase
# machine: which situations raise an event, that each raises exactly one, and
# that a fixed reviewer finding stops being counted.
load helpers

setup() {
  setup_home; make_project xyz
  export PATH="$BATS_TEST_DIRNAME/fakebin:$PATH"
  export RY_FAKE_FORGE_LOG="$BATS_TEST_TMPDIR/forge.log"
  export RY_FAKE_GH_VIEW="$BATS_TEST_TMPDIR/gh.json" RY_FAKE_GLAB_VIEW="$BATS_TEST_TMPDIR/glab.json"
  export RY_FAKE_GH_THREADS="$BATS_TEST_TMPDIR/threads.json"
  ID=$(ry-dispatch.sh --haul --mode pr xyz "add dark mode" | sed -n 's/^id=//p')
  SIDING="$RY_HOME/yard/xyz/$ID"
  git -C "$SIDING" config user.email e@e; git -C "$SIDING" config user.name e
  echo x > "$SIDING/dark.css"; git -C "$SIDING" add -A; git -C "$SIDING" commit -qm "add dark mode css"
  EV="$RY_HOME/state/events.log"
}

gh_pr() {  # <mergeStateStatus> <conclusion...>
  local ms=$1; shift
  local rollup="" c
  for c in "$@"; do rollup+="${rollup:+,}{\"status\":\"COMPLETED\",\"conclusion\":\"$c\"}"; done
  printf '{"state":"OPEN","mergeStateStatus":"%s","statusCheckRollup":[%s]}\n' "$ms" "$rollup" > "$RY_FAKE_GH_VIEW"
}
open_gh() { RY_FORGE=github ry-pr.sh "$ID" >/dev/null; }
open_gl() { RY_FORGE=gitlab ry-pr.sh "$ID" >/dev/null; }

# --- GitHub: what "ready" is ------------------------------------------------

@test "an open, mergeable, all-green PR raises exactly one pr-ready with its url" {
  open_gh
  gh_pr CLEAN SUCCESS SUCCESS SUCCESS
  run ry-pr-poll.sh "$ID"
  [ "$status" -eq 0 ]
  # This is the assertion that fails if the pr-ready emission is deleted.
  grep -q " $ID pr-ready https://github.com/o/r/pull/7 checks=3 findings=0 worst=none$" "$EV"
  ry-pr-poll.sh "$ID" >/dev/null
  ry-pr-poll.sh "$ID" >/dev/null
  [ "$(grep -c "pr-ready" "$EV")" -eq 1 ]
}

@test "a mergeable PR with no checks at all says so instead of pr-ready" {
  open_gh
  gh_pr CLEAN
  run ry-pr-poll.sh "$ID"
  [ "$status" -eq 0 ]
  [[ "$output" == *"checks=none"* ]]
  ! grep -q "pr-ready" "$EV"
  grep -q " $ID pr-no-checks https://github.com/o/r/pull/7 " "$EV"
}

@test "a conflicting PR raises pr-conflict and never pr-ready" {
  open_gh
  gh_pr DIRTY SUCCESS
  run ry-pr-poll.sh "$ID"
  [ "$status" -eq 0 ]
  [[ "$output" == *"merge=dirty"* ]]
  ! grep -q "pr-ready" "$EV"
  grep -q " $ID pr-conflict https://github.com/o/r/pull/7$" "$EV"
  ry-pr-poll.sh "$ID" >/dev/null
  [ "$(grep -c "pr-conflict" "$EV")" -eq 1 ]
}

@test "a PR blocked on a required review is not ready and is not a conflict" {
  open_gh
  gh_pr BLOCKED SUCCESS
  run ry-pr-poll.sh "$ID"
  [ "$status" -eq 0 ]
  [[ "$output" == *"merge=blocked"* ]]
  [ ! -s "$EV" ] || ! grep -q "pr-" "$EV"
}

@test "a transient UNKNOWN mergeability does not suppress the event forever" {
  open_gh
  gh_pr UNKNOWN SUCCESS
  run ry-pr-poll.sh "$ID"
  [ "$status" -eq 0 ]
  [[ "$output" == *"merge=unknown"* ]]
  [ ! -e "$RY_HOME/state/$ID.pr-phase" ]
  ! grep -q "pr-ready" "$EV" 2>/dev/null
  # GitHub finishes recomputing; the event must still arrive.
  gh_pr CLEAN SUCCESS
  ry-pr-poll.sh "$ID" >/dev/null
  [ "$(grep -c "pr-ready" "$EV")" -eq 1 ]
}

@test "UNKNOWN in the middle of a green run does not re-fire pr-ready" {
  open_gh
  gh_pr CLEAN SUCCESS
  ry-pr-poll.sh "$ID" >/dev/null
  gh_pr UNKNOWN SUCCESS
  ry-pr-poll.sh "$ID" >/dev/null
  gh_pr CLEAN SUCCESS
  ry-pr-poll.sh "$ID" >/dev/null
  [ "$(grep -c "pr-ready" "$EV")" -eq 1 ]
}

@test "green, then red, then green again reports each transition once" {
  open_gh
  gh_pr CLEAN SUCCESS
  ry-pr-poll.sh "$ID" >/dev/null
  gh_pr CLEAN FAILURE
  ry-pr-poll.sh "$ID" >/dev/null
  gh_pr CLEAN SUCCESS
  ry-pr-poll.sh "$ID" >/dev/null
  [ "$(grep -c "pr-checks-failed" "$EV")" -eq 1 ]
  [ "$(grep -c "pr-ready" "$EV")" -eq 2 ]
}

# --- GitHub: what counts as a finding ---------------------------------------

# Four CodeRabbit threads, shaped like the real ones on this repo's PRs #12 and
# #15: two Major ones since resolved, one Major gone stale on code that moved,
# one Major the bot marked addressed without deleting, and one live Minor.
# A naive count says 5 findings, worst major. One of them is real.
threads() {
  cat > "$RY_FAKE_GH_THREADS" <<'JSON'
{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[
 {"isResolved":true,"isOutdated":true,"comments":{"nodes":[{"body":"_🗄️ Data Integrity_ | _🟠 Major_\n\n**Do not rerun setup.**"}]}},
 {"isResolved":true,"isOutdated":false,"comments":{"nodes":[{"body":"_🩺 Stability_ | _🟠 Major_\n\n**Validate RY_START_TIMEOUT.**"}]}},
 {"isResolved":false,"isOutdated":true,"comments":{"nodes":[{"body":"_🩺 Stability_ | _🟠 Major_\n\n**Validate the fallback.**"}]}},
 {"isResolved":false,"isOutdated":false,"comments":{"nodes":[{"body":"_🎯 Correctness_ | _🟠 Major_\n\n**Missing --yes.**\n\nAddressed in commits abc123 to def456."}]}},
 {"isResolved":false,"isOutdated":false,"comments":{"nodes":[{"body":"_📐 Maintainability_ | _🟡 Minor_\n\n**Remove the duplicate or.**"}]}}
]}}}}}
JSON
}

@test "a resolved, outdated or addressed finding is not counted" {
  open_gh
  threads
  gh_pr CLEAN SUCCESS
  run ry-pr-poll.sh "$ID"
  [ "$status" -eq 0 ]
  # This is the assertion that fails if the addressed-finding exclusion is
  # removed: without it the count is 5 and the worst severity is major.
  grep -q " $ID pr-ready https://github.com/o/r/pull/7 checks=1 findings=1 worst=minor$" "$EV"
  ! grep -q "findings=5" "$EV"
  ! grep -q "worst=major" "$EV"
}

@test "every finding resolved reads as no findings" {
  open_gh
  cat > "$RY_FAKE_GH_THREADS" <<'JSON'
{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[
 {"isResolved":true,"isOutdated":false,"comments":{"nodes":[{"body":"_x_ | _🟠 Major_\n\n**a**"}]}},
 {"isResolved":true,"isOutdated":false,"comments":{"nodes":[{"body":"_x_ | _🔴 Critical_\n\n**b**"}]}}
]}}}}}
JSON
  gh_pr CLEAN SUCCESS
  ry-pr-poll.sh "$ID" >/dev/null
  grep -q "findings=0 worst=none$" "$EV"
}

@test "the worst live severity is the one reported" {
  open_gh
  cat > "$RY_FAKE_GH_THREADS" <<'JSON'
{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[
 {"isResolved":false,"isOutdated":false,"comments":{"nodes":[{"body":"_x_ | _🟡 Minor_\n\n**a**"}]}},
 {"isResolved":false,"isOutdated":false,"comments":{"nodes":[{"body":"_x_ | _🔴 Critical_\n\n**b**"}]}},
 {"isResolved":false,"isOutdated":false,"comments":{"nodes":[{"body":"_x_ | _🧹 Nitpick_\n\n**c**"}]}}
]}}}}}
JSON
  gh_pr CLEAN SUCCESS
  ry-pr-poll.sh "$ID" >/dev/null
  grep -q "findings=3 worst=critical$" "$EV"
}

@test "the event carries no review prose" {
  open_gh
  threads
  gh_pr CLEAN SUCCESS
  ry-pr-poll.sh "$ID" >/dev/null
  ! grep -q "duplicate" "$EV"
  ! grep -q "Missing" "$EV"
}

@test "findings are only looked up when the PR is otherwise ready" {
  open_gh
  gh_pr CLEAN FAILURE
  ry-pr-poll.sh "$ID" >/dev/null
  ! grep -q "api graphql" "$RY_FAKE_FORGE_LOG"
}

# --- GitLab has its own answers ---------------------------------------------

gl_mr() {  # <detailed_merge_status> <pipeline-status|-> [state]
  local pipe=""
  [ "$2" = - ] || pipe=",\"head_pipeline\":{\"status\":\"$2\"}"
  printf '{"state":"%s","detailed_merge_status":"%s"%s}\n' "${3:-opened}" "$1" "$pipe" > "$RY_FAKE_GLAB_VIEW"
}

@test "gitlab: mergeable with a green pipeline is pr-ready, with findings n/a" {
  open_gl
  gl_mr mergeable success
  run ry-pr-poll.sh "$ID"
  [ "$status" -eq 0 ]
  [ "$output" = "state=open checks=success merge=clean findings=n/a" ]
  grep -q " $ID pr-ready https://gitlab.example.com/grp/sub/r/-/merge_requests/12 checks=1 findings=n/a worst=n/a$" "$EV"
  ry-pr-poll.sh "$ID" >/dev/null
  [ "$(grep -c "pr-ready" "$EV")" -eq 1 ]
  # No reviewer API is called on GitLab: the number would be invented.
  ! grep -q "api" "$RY_FAKE_FORGE_LOG"
}

@test "gitlab: a conflicting MR is pr-conflict, not pr-ready" {
  open_gl
  gl_mr conflict success
  run ry-pr-poll.sh "$ID"
  [[ "$output" == *"merge=dirty"* ]]
  grep -q " $ID pr-conflict " "$EV"
  ! grep -q "pr-ready" "$EV"
}

@test "gitlab: 'checking' is transient and recovers, like GitHub's UNKNOWN" {
  open_gl
  gl_mr checking success
  run ry-pr-poll.sh "$ID"
  [[ "$output" == *"merge=unknown"* ]]
  [ ! -e "$RY_HOME/state/$ID.pr-phase" ]
  gl_mr mergeable success
  ry-pr-poll.sh "$ID" >/dev/null
  [ "$(grep -c "pr-ready" "$EV")" -eq 1 ]
}

@test "gitlab: mergeable with no pipeline at all is pr-no-checks" {
  open_gl
  gl_mr mergeable -
  run ry-pr-poll.sh "$ID"
  [[ "$output" == *"checks=none"* ]]
  grep -q " $ID pr-no-checks " "$EV"
  ! grep -q "pr-ready" "$EV"
}

@test "gitlab: an MR waiting on discussions is not ready" {
  open_gl
  gl_mr discussions_not_resolved success
  run ry-pr-poll.sh "$ID"
  [[ "$output" == *"merge=blocked"* ]]
  ! grep -q "pr-ready" "$EV"
}

# --- the watcher must still be polling when all this happens (#10) ----------

@test "a turn end after the PR opened does not stop the watcher polling it" {
  open_gl
  RY_ID=$ID ry-engine-stop.sh <<<"{\"transcript_path\":\"$BATS_TEST_DIRNAME/fixtures/transcript.jsonl\",\"stop_hook_active\":false}"
  [ "$(cat "$RY_HOME/state/$ID.status")" = "turn-ended" ]
  gl_mr mergeable success
  RY_PR_POLL_SEC=0 run ry-watch.sh --once
  [ "$status" -eq 0 ]
  grep -q "engine $ID pr-ready: https://gitlab.example.com/grp/sub/r/-/merge_requests/12" "$RY_HOME/state/inbox.md"
}

@test "a PR merged after a turn end is still noticed and the queue moves" {
  B=$(ry-dispatch.sh --haul --after "$ID" xyz "waiter" | sed -n 's/^id=//p')
  open_gl
  RY_ID=$ID ry-engine-stop.sh <<<"{\"transcript_path\":\"$BATS_TEST_DIRNAME/fixtures/transcript.jsonl\",\"stop_hook_active\":false}"
  gl_mr mergeable success merged
  RY_PR_POLL_SEC=0 ry-watch.sh --once
  [ "$(cat "$RY_HOME/state/$ID.status")" = "merged" ]
  RY_PR_POLL_SEC=0 ry-watch.sh --once
  [ "$(cat "$RY_HOME/state/$B.status")" = "dispatched" ]
  grep -q "engine $B coupled" "$RY_HOME/state/inbox.md"
}

@test "a merged PR is not polled again" {
  open_gl
  gl_mr mergeable success merged
  RY_PR_POLL_SEC=0 ry-watch.sh --once
  n=$(grep -c "mr view" "$RY_FAKE_FORGE_LOG")
  RY_PR_POLL_SEC=0 ry-watch.sh --once
  [ "$(grep -c "mr view" "$RY_FAKE_FORGE_LOG")" -eq "$n" ]
}
