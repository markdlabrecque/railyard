#!/usr/bin/env bats
load helpers
setup() { setup_home; setup_herdr; make_project xyz; }
teardown() { pid=$(cat "$RY_HOME/state/.watch.lock" 2>/dev/null); [ -n "$pid" ] && kill "$pid" 2>/dev/null || true; }

@test "herdr dispatch opens a labelled tab on the siding and records tab and pane" {
  run ry-dispatch.sh --haul xyz "fix it"
  [ "$status" -eq 0 ]
  id=$(sed -n 's/^id=//p' <<<"$output")
  grep -q -- "tab create --cwd $RY_HOME/yard/xyz/$id --label ry-$id --no-focus" "$RY_FAKE_HERDR_LOG"
  grep -q -- "pane run pane-fake-.* export CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION" "$RY_FAKE_HERDR_LOG"
  grep -q -- "--dangerously-skip-permissions --settings $RY_HOME/state/$id.settings.json" "$RY_FAKE_HERDR_LOG"
  grep -q '^backend=herdr$' "$RY_HOME/state/$id.meta"
  # both ids travel in one target: the pane to talk to, the tab to close
  grep -q '^target=tab:tab-fake-[0-9]*/pane:pane-fake-[0-9]*$' "$RY_HOME/state/$id.meta"
  [ "$(cat "$RY_HOME/state/$id.status")" = "running" ]
}

@test "herdr decouple closes the tab, not the pane" {
  id=$(ry-dispatch.sh --haul xyz "x" | sed -n 's/^id=//p')
  target=$(sed -n 's/^target=//p' "$RY_HOME/state/$id.meta")
  tab=${target#tab:}; tab=${tab%%/pane:*}
  run ry-decouple.sh --force "$id"
  [ "$status" -eq 0 ]
  grep -q -- "tab close $tab" "$RY_FAKE_HERDR_LOG"
}

@test "herdr peek and send work through the backend" {
  id=$(ry-dispatch.sh --haul xyz "x" | sed -n 's/^id=//p')
  target=$(sed -n 's/^target=//p' "$RY_HOME/state/$id.meta")
  pane=${target##*/pane:}
  run ry-peek.sh "$id"
  [ "$status" -eq 0 ]; [[ "$output" == *"line two"* ]]
  grep -q -- "pane read $pane --source recent-unwrapped --lines 200" "$RY_FAKE_HERDR_LOG"
  run ry-send.sh "$id" "please also update the docs"
  [ "$status" -eq 0 ]
  # this pane is not a recognised agent, so send falls back to literal text + enter
  grep -q -- "agent prompt $pane please also update the docs" "$RY_FAKE_HERDR_LOG"
  grep -q -- "pane send-text $pane please also update the docs" "$RY_FAKE_HERDR_LOG"
  grep -q -- "pane send-keys $pane enter" "$RY_FAKE_HERDR_LOG"
  [ "$(cat "$RY_HOME/state/$id.status")" = "running" ]
}

@test "herdr wake: session start records HERDR_PANE_ID and watch prompts it" {
  printf 'tab-ym pane-ym yardmaster\n' >> "$RY_FAKE_HERDR_TABS"
  HERDR_PANE_ID=pane-ym run ry-session-start.sh <<<'{}'
  [ "$(claim_target)" = "pane-ym" ]
  [ "$(claim_backend)" = herdr ]
  kill "$(cat "$RY_HOME/state/.watch.lock")"
  id=$(ry-dispatch.sh --haul xyz "x" | sed -n 's/^id=//p')
  RY_ID=$id ry-engine-stop.sh <<<"{\"transcript_path\":\"$BATS_TEST_DIRNAME/fixtures/transcript.jsonl\",\"stop_hook_active\":false}"
  run ry-watch.sh --once
  grep -q -- "agent prompt pane-ym \[railyard\] engine $id turn-ended: DONE" "$RY_FAKE_HERDR_LOG"
}

@test "a second herdr session is told another yardmaster holds the yard" {
  printf 'tab-first pane-first yardmaster\n' >> "$RY_FAKE_HERDR_TABS"   # herdr still shows it
  HERDR_PANE_ID=pane-first ry-session-start.sh <<<'{}' >/dev/null
  HERDR_PANE_ID=pane-second run ry-session-start.sh <<<'{}'
  [[ "$output" == *"another yardmaster"* ]]
  [ "$(claim_target)" = "pane-first" ]
}

@test "a herdr session takes the yard when the holding pane is gone" {
  printf 'tab-first pane-first yardmaster\n' >> "$RY_FAKE_HERDR_TABS"
  HERDR_PANE_ID=pane-first ry-session-start.sh <<<'{}' >/dev/null
  : > "$RY_FAKE_HERDR_TABS"   # that tab was closed
  printf 'tab-second pane-second yardmaster\n' >> "$RY_FAKE_HERDR_TABS"
  HERDR_PANE_ID=pane-second run ry-session-start.sh <<<'{}'
  [[ "$output" == *"you are the yardmaster"* ]]
  [ "$(claim_target)" = "pane-second" ]
}

@test "ry-yard.sh --dry-run carries the herdr backend into the yardmaster" {
  run ry-yard.sh --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"RY_BACKEND=herdr"* ]]
}
