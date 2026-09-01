#!/usr/bin/env bats
load helpers

setup() {
  setup_home; make_project xyz
  export PATH="$BATS_TEST_DIRNAME/fakebin:$PATH"
  export RY_FAKE_FORGE_LOG="$BATS_TEST_TMPDIR/forge.log"
  export RY_FAKE_GH_VIEW="$BATS_TEST_TMPDIR/gh.json" RY_FAKE_GLAB_VIEW="$BATS_TEST_TMPDIR/glab.json"
  ID=$(ry-dispatch.sh --haul --mode pr xyz "add dark mode" | sed -n 's/^id=//p')
  SIDING="$RY_HOME/yard/xyz/$ID"; PDIR="$RY_HOME/projects/xyz"
  git -C "$SIDING" config user.email e@e; git -C "$SIDING" config user.name e
  echo x > "$SIDING/dark.css"; git -C "$SIDING" add -A; git -C "$SIDING" commit -qm "add dark mode css"
}
lib() { bash -c ". '$BATS_TEST_DIRNAME/../bin/ry-forge-lib.sh'; $*"; }

@test "forge detection: github.com -> github, anything else -> gitlab" {
  [ "$(lib ry_forge_from_url git@github.com:o/r.git)" = github ]
  [ "$(lib ry_forge_from_url https://github.com/o/r)" = github ]
  [ "$(lib ry_forge_from_url git@git.example.com:grp/sub/r.git)" = gitlab ]
  [ "$(lib ry_forge_from_url https://gitlab.example.com/grp/r.git)" = gitlab ]
}

@test "pr on gitlab: pushes branch, runs glab mr create, records url and status" {
  RY_FORGE=gitlab run ry-pr.sh "$ID"
  [ "$status" -eq 0 ]
  [[ "$output" == *"merge_requests/12"* ]]
  git -C "$PDIR" fetch -q; git -C "$PDIR" rev-parse --verify -q "origin/ry/$ID" >/dev/null
  grep -q -- "--source-branch ry/$ID" "$RY_FAKE_FORGE_LOG"
  grep -q -- "--target-branch main" "$RY_FAKE_FORGE_LOG"
  grep -q -- "--title add dark mode css" "$RY_FAKE_FORGE_LOG"
  grep -q '^pr_url=https://gitlab.example.com/grp/sub/r/-/merge_requests/12$' "$RY_HOME/state/$ID.meta"
  grep -q '^forge=gitlab$' "$RY_HOME/state/$ID.meta"
  [ "$(cat "$RY_HOME/state/$ID.status")" = "pr-open" ]
}

@test "pr on github: runs gh pr create" {
  RY_FORGE=github run ry-pr.sh "$ID"
  [ "$status" -eq 0 ]
  grep -q -- "gh pr create" "$RY_FAKE_FORGE_LOG"
  grep -q -- "--head ry/$ID" "$RY_FAKE_FORGE_LOG"
  grep -q '^pr_url=https://github.com/o/r/pull/7$' "$RY_HOME/state/$ID.meta"
}

@test "pr refuses local-only mode, dirty siding, and a second open" {
  L=$(ry-dispatch.sh --haul xyz "t" | sed -n 's/^id=//p')
  RY_FORGE=gitlab run ry-pr.sh "$L"; [ "$status" -ne 0 ]
  echo y > "$SIDING/dirty.txt"
  RY_FORGE=gitlab run ry-pr.sh "$ID"; [ "$status" -ne 0 ]; [[ "$output" == *"uncommitted"* ]]
  rm "$SIDING/dirty.txt"
  RY_FORGE=gitlab ry-pr.sh "$ID" >/dev/null
  RY_FORGE=gitlab run ry-pr.sh "$ID"; [ "$status" -ne 0 ]; [[ "$output" == *"already"* ]]
}

@test "pr-poll gitlab: open+running, then merged -> status merged + event" {
  RY_FORGE=gitlab ry-pr.sh "$ID" >/dev/null
  echo '{"state":"opened","head_pipeline":{"status":"running"}}' > "$RY_FAKE_GLAB_VIEW"
  run ry-pr-poll.sh "$ID"
  [ "$status" -eq 0 ]; [ "$output" = "state=open checks=pending merge=unknown findings=-" ]
  grep -q -- "mr view 12" "$RY_FAKE_FORGE_LOG"
  echo '{"state":"merged","head_pipeline":{"status":"success"}}' > "$RY_FAKE_GLAB_VIEW"
  run ry-pr-poll.sh "$ID"
  [ "$output" = "state=merged checks=success merge=unknown findings=-" ]
  [ "$(cat "$RY_HOME/state/$ID.status")" = "merged" ]
  grep -q " $ID pr-merged https://gitlab.example.com/grp/sub/r/-/merge_requests/12$" "$RY_HOME/state/events.log"
}

@test "pr-poll github: failed checks raise one event, and aggregate the rollup" {
  RY_FORGE=github ry-pr.sh "$ID" >/dev/null
  echo '{"state":"OPEN","mergeStateStatus":"CLEAN","statusCheckRollup":[{"status":"COMPLETED","conclusion":"FAILURE"},{"status":"COMPLETED","conclusion":"SUCCESS"}]}' > "$RY_FAKE_GH_VIEW"
  run ry-pr-poll.sh "$ID"
  [ "$output" = "state=open checks=failure merge=clean findings=-" ]
  run ry-pr-poll.sh "$ID"
  [ "$(grep -c "pr-checks-failed" "$RY_HOME/state/events.log")" -eq 1 ]
  echo '{"state":"OPEN","mergeStateStatus":"CLEAN","statusCheckRollup":[{"status":"COMPLETED","conclusion":"SUCCESS"},{"status":"COMPLETED","conclusion":"NEUTRAL"}]}' > "$RY_FAKE_GH_VIEW"
  run ry-pr-poll.sh "$ID"
  [ "$output" = "state=open checks=success merge=clean findings=0" ]
  echo '{"state":"OPEN","mergeStateStatus":"CLEAN","statusCheckRollup":[{"status":"IN_PROGRESS"}]}' > "$RY_FAKE_GH_VIEW"
  run ry-pr-poll.sh "$ID"
  [ "$output" = "state=open checks=pending merge=clean findings=-" ]
  echo '{"state":"OPEN","mergeStateStatus":"CLEAN","statusCheckRollup":[]}' > "$RY_FAKE_GH_VIEW"
  run ry-pr-poll.sh "$ID"
  [ "$output" = "state=open checks=none merge=clean findings=0" ]
}

@test "watch polls open PRs and turns pr-merged into an inbox line with the url" {
  RY_FORGE=gitlab ry-pr.sh "$ID" >/dev/null
  echo '{"state":"merged","head_pipeline":{"status":"success"}}' > "$RY_FAKE_GLAB_VIEW"
  RY_PR_POLL_SEC=0 run ry-watch.sh --once
  [ "$status" -eq 0 ]
  grep -q "engine $ID pr-merged: https://gitlab.example.com/grp/sub/r/-/merge_requests/12" "$RY_HOME/state/inbox.md"
}

@test "watch respects the PR poll interval" {
  RY_FORGE=gitlab ry-pr.sh "$ID" >/dev/null
  echo '{"state":"opened","head_pipeline":{"status":"running"}}' > "$RY_FAKE_GLAB_VIEW"
  RY_PR_POLL_SEC=3600 run ry-watch.sh --once
  RY_PR_POLL_SEC=3600 run ry-watch.sh --once
  [ "$(grep -c "mr view" "$RY_FAKE_FORGE_LOG")" -eq 1 ]
}

@test "watch polls again once the interval has elapsed" {
  RY_FORGE=gitlab ry-pr.sh "$ID" >/dev/null
  echo '{"state":"opened","head_pipeline":{"status":"running"}}' > "$RY_FAKE_GLAB_VIEW"
  RY_PR_POLL_SEC=120 ry-watch.sh --once
  [ "$(grep -c "mr view" "$RY_FAKE_FORGE_LOG")" -eq 1 ]
  RY_PR_POLL_SEC=120 ry-watch.sh --once
  [ "$(grep -c "mr view" "$RY_FAKE_FORGE_LOG")" -eq 1 ]
  # wind the clock back past the interval; the next pass must poll again
  printf '%s\n' "$(( $(date +%s) - 121 ))" > "$RY_HOME/state/$ID.pr-polled"
  RY_PR_POLL_SEC=120 ry-watch.sh --once
  [ "$(grep -c "mr view" "$RY_FAKE_FORGE_LOG")" -eq 2 ]
}

@test "pr without --auto-merge writes no auto_merge= line and never calls merge" {
  RY_FORGE=gitlab run ry-pr.sh "$ID"
  [ "$status" -eq 0 ]
  ! grep -q '^auto_merge=' "$RY_HOME/state/$ID.meta"
  ! grep -q "mr merge" "$RY_FAKE_FORGE_LOG"
}

@test "pr --auto-merge writes auto_merge=merge and never calls merge itself" {
  RY_FORGE=gitlab run ry-pr.sh --auto-merge "$ID"
  [ "$status" -eq 0 ]
  grep -q '^auto_merge=merge$' "$RY_HOME/state/$ID.meta"
  [ "$(cat "$RY_HOME/state/$ID.status")" = "pr-open" ]
  ! grep -q "mr merge" "$RY_FAKE_FORGE_LOG"
}

@test "pr --auto-merge-method squash writes auto_merge=squash" {
  RY_FORGE=github run ry-pr.sh --auto-merge --auto-merge-method squash "$ID"
  [ "$status" -eq 0 ]
  grep -q '^auto_merge=squash$' "$RY_HOME/state/$ID.meta"
  ! grep -q "pr merge" "$RY_FAKE_FORGE_LOG"
}

@test "pr --auto-merge-method without --auto-merge is an error" {
  RY_FORGE=gitlab run ry-pr.sh --auto-merge-method squash "$ID"
  [ "$status" -ne 0 ]
}

@test "pr --auto-merge-method as the trailing argument with no value is an error, not a crash" {
  RY_FORGE=gitlab run ry-pr.sh --auto-merge --auto-merge-method
  [ "$status" -ne 0 ]
  [[ "$output" == *"needs a value"* ]]
}

@test "watch turns failing checks into one inbox line with the url" {
  RY_FORGE=gitlab ry-pr.sh "$ID" >/dev/null
  echo '{"state":"opened","head_pipeline":{"status":"failed"}}' > "$RY_FAKE_GLAB_VIEW"
  RY_PR_POLL_SEC=0 ry-watch.sh --once
  grep -q "engine $ID pr-checks-failed: https://gitlab.example.com/grp/sub/r/-/merge_requests/12" "$RY_HOME/state/inbox.md"
  RY_PR_POLL_SEC=0 ry-watch.sh --once
  [ "$(grep -c "pr-checks-failed" "$RY_HOME/state/inbox.md")" -eq 1 ]
}
