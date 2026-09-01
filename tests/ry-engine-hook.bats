#!/usr/bin/env bats
# The Stop hook must survive a session restart. --resume drops every argv
# flag (see issue #5), so the hook cannot live only in --settings; it must
# also be registered in the siding itself, where Claude Code reads project
# settings regardless of how the session started.
load helpers

setup() {
  setup_home; setup_tmux; make_project xyz
  T="$BATS_TEST_DIRNAME/fixtures/transcript.jsonl"
}
teardown() { teardown_tmux; }

wait_for_log() { for _ in $(seq 1 50); do [ -s "$RY_FAKE_CLAUDE_LOG" ] && return 0; sleep 0.1; done; return 1; }

# --- the reproduction: a resumed session has no --settings at all ----------

@test "a resumed engine (no --settings) still reports turn-end via the siding hook" {
  run ry-dispatch.sh --haul xyz "task"
  [ "$status" -eq 0 ]
  id=$(sed -n 's/^id=//p' <<<"$output")
  wait_for_log
  siding="$RY_HOME/yard/xyz/$id"

  # This is what a --resume relaunch has left: no --settings on argv, nothing
  # but whatever the siding itself registers.
  [ -f "$siding/.claude/settings.local.json" ]
  cmd=$(jq -r '[.hooks.Stop[]?.hooks[]? | select(.command | test("ry-engine-stop.sh")) | .command] | first' \
    "$siding/.claude/settings.local.json")
  [ -n "$cmd" ] && [ "$cmd" != null ]

  RY_ID=$id bash -c "$cmd" <<<"{\"session_id\":\"resumed-1\",\"transcript_path\":\"$T\",\"stop_hook_active\":false}"

  [ "$(cat "$RY_HOME/state/$id.status")" = "turn-ended" ]
  grep -q " $id turn-ended$" "$RY_HOME/state/events.log"
}

# --- registration itself -----------------------------------------------

@test "launch writes a siding-local Stop hook naming ry-engine-stop.sh" {
  id=$(ry-dispatch.sh --haul xyz "task" | sed -n 's/^id=//p')
  wait_for_log
  siding="$RY_HOME/yard/xyz/$id"
  jq -e '[.hooks.Stop[]?.hooks[]?.command] | any(test("ry-engine-stop.sh"))' \
    "$siding/.claude/settings.local.json"
}

@test "the --settings argv path still registers the hook too (no regression)" {
  id=$(ry-dispatch.sh --haul xyz "task" | sed -n 's/^id=//p')
  wait_for_log
  jq -e '.hooks.Stop[0].hooks[0].command | test("ry-engine-stop.sh")' \
    "$RY_HOME/state/$id.settings.json"
  args=$(sed -n '2,$p' "$RY_FAKE_CLAUDE_LOG")
  [[ "$args" == *"--settings $RY_HOME/state/$id.settings.json"* ]]
}

@test "rerunning launch does not duplicate the railyard hook in the siding" {
  id=$(ry-dispatch.sh --haul xyz "task" | sed -n 's/^id=//p')
  wait_for_log
  siding="$RY_HOME/yard/xyz/$id"
  ry-engine-launch.sh "$id"
  count=$(jq '[.hooks.Stop[]?.hooks[]? | select(.command | test("ry-engine-stop.sh"))] | length' \
    "$siding/.claude/settings.local.json")
  [ "$count" -eq 1 ]
}

@test "launch merges the hook into an existing settings.local.json, preserving other keys" {
  RY_BACKEND=none run ry-dispatch.sh --haul xyz "task"
  [ "$status" -eq 0 ]
  id=$(sed -n 's/^id=//p' <<<"$output")
  siding="$RY_HOME/yard/xyz/$id"
  [ -d "$siding" ]
  mkdir -p "$siding/.claude"
  cat > "$siding/.claude/settings.local.json" <<'JSON'
{"permissions":{"allow":["Bash(ls:*)"]},"hooks":{"Stop":[{"hooks":[{"type":"command","command":"exec /some/other/hook.sh"}]}]}}
JSON
  ry-engine-launch.sh "$id"
  jq -e '.permissions.allow == ["Bash(ls:*)"]' "$siding/.claude/settings.local.json"
  jq -e '[.hooks.Stop[]?.hooks[]?.command] | any(test("other/hook.sh"))' "$siding/.claude/settings.local.json"
  jq -e '[.hooks.Stop[]?.hooks[]?.command] | any(test("ry-engine-stop.sh"))' "$siding/.claude/settings.local.json"
}

@test "launch never touches a tracked .claude/settings.json" {
  mkdir -p "$RY_HOME/projects/xyz/.claude"
  echo '{"hooks":{"SessionStart":[]}}' > "$RY_HOME/projects/xyz/.claude/settings.json"
  ( cd "$RY_HOME/projects/xyz" && git add -A && git commit -qm settings && git push -q origin HEAD )
  id=$(ry-dispatch.sh --haul xyz "task" | sed -n 's/^id=//p')
  wait_for_log
  siding="$RY_HOME/yard/xyz/$id"
  diff "$RY_HOME/projects/xyz/.claude/settings.json" "$siding/.claude/settings.json"
}

# --- the siding must not go dirty -------------------------------------

@test "launch leaves the siding clean and adds settings.local.json to git's exclude file" {
  id=$(ry-dispatch.sh --haul xyz "task" | sed -n 's/^id=//p')
  wait_for_log
  siding="$RY_HOME/yard/xyz/$id"
  [ -z "$(git -C "$siding" status --porcelain)" ]
  common=$(git -C "$siding" rev-parse --git-common-dir)
  grep -qxF '.claude/settings.local.json*' "$common/info/exclude"
}

@test "the exclude line is written once even if launch runs twice" {
  id=$(ry-dispatch.sh --haul xyz "task" | sed -n 's/^id=//p')
  wait_for_log
  siding="$RY_HOME/yard/xyz/$id"
  ry-engine-launch.sh "$id"
  common=$(git -C "$siding" rev-parse --git-common-dir)
  [ "$(grep -c -F '.claude/settings.local.json' "$common/info/exclude")" -eq 1 ]
}

@test "when the project already gitignores settings.local.json, launch still leaves the siding clean" {
  echo '.claude/settings.local.json' >> "$RY_HOME/projects/xyz/.gitignore"
  ( cd "$RY_HOME/projects/xyz" && git add -A && git commit -qm gitignore && git push -q origin HEAD )
  id=$(ry-dispatch.sh --haul xyz "task" | sed -n 's/^id=//p')
  wait_for_log
  siding="$RY_HOME/yard/xyz/$id"
  [ -z "$(git -C "$siding" status --porcelain)" ]
}

# --- ry-engine-stop.sh must never swallow a turn end ---------------------
# The hook is registered in two places now, but Claude Code fires an identical
# hook command once however many settings sources name it, so this script does
# no de-duplication of its own. These guard that: whatever a future change
# thinks it knows about duplicates, a real turn end always gets reported.

@test "a second invocation under a new session id still reports" {
  id=$(ry-dispatch.sh --haul xyz "task" | sed -n 's/^id=//p')
  wait_for_log
  RY_ID=$id ry-engine-stop.sh <<<"{\"session_id\":\"s1\",\"transcript_path\":\"$T\",\"stop_hook_active\":false}"
  RY_ID=$id ry-engine-stop.sh <<<"{\"session_id\":\"s2\",\"transcript_path\":\"$T\",\"stop_hook_active\":false}"
  [ "$(grep -c " $id turn-ended$" "$RY_HOME/state/events.log")" -eq 2 ]
}

@test "a second invocation on a grown transcript still reports" {
  id=$(ry-dispatch.sh --haul xyz "task" | sed -n 's/^id=//p')
  wait_for_log
  tp="$BATS_TEST_TMPDIR/t.jsonl"
  cp "$T" "$tp"
  RY_ID=$id ry-engine-stop.sh <<<"{\"session_id\":\"s1\",\"transcript_path\":\"$tp\",\"stop_hook_active\":false}"
  echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"DONE: second turn."}]}}' >> "$tp"
  RY_ID=$id ry-engine-stop.sh <<<"{\"session_id\":\"s1\",\"transcript_path\":\"$tp\",\"stop_hook_active\":false}"
  [ "$(grep -c " $id turn-ended$" "$RY_HOME/state/events.log")" -eq 2 ]
}

@test "a second identical invocation with no session id still reports" {
  id=$(ry-dispatch.sh --haul xyz "task" | sed -n 's/^id=//p')
  wait_for_log
  RY_ID=$id ry-engine-stop.sh <<<"{\"transcript_path\":\"$T\",\"stop_hook_active\":false}"
  RY_ID=$id ry-engine-stop.sh <<<"{\"transcript_path\":\"$T\",\"stop_hook_active\":false}"
  [ "$(grep -c " $id turn-ended$" "$RY_HOME/state/events.log")" -eq 2 ]
}

@test "a second identical invocation with an unreadable transcript still reports" {
  id=$(ry-dispatch.sh --haul xyz "task" | sed -n 's/^id=//p')
  wait_for_log
  RY_ID=$id ry-engine-stop.sh <<<"{\"session_id\":\"s1\",\"transcript_path\":\"/no/such/file.jsonl\",\"stop_hook_active\":false}"
  RY_ID=$id ry-engine-stop.sh <<<"{\"session_id\":\"s1\",\"transcript_path\":\"/no/such/file.jsonl\",\"stop_hook_active\":false}"
  [ "$(grep -c " $id turn-ended$" "$RY_HOME/state/events.log")" -eq 2 ]
}
