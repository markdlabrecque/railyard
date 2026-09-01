#!/usr/bin/env bats
# Doc-wiring checks for the open-decisions queue (issue #7). These assert
# against the repo's own files (SKILL.md, AGENTS.md), not against a yard
# fixture — there is no RY_HOME here on purpose.
load helpers

setup() {
  repo="$BATS_TEST_DIRNAME/.."
  skill="$repo/.claude/skills/shed/SKILL.md"
  agents="$repo/AGENTS.md"
}

@test "shed SKILL.md instructs writing state/open-decisions.md before reporting" {
  grep -q 'state/open-decisions.md' "$skill"
}

@test "shed SKILL.md's open-decisions step names one line per item and the task id" {
  grep -q 'open-decisions.md' "$skill"
  # the step describing open-decisions.md talks about "one line" per item and
  # carrying the task id where there is one — not just a bare file mention.
  grep -A2 -B2 'open-decisions.md' "$skill" | grep -qi 'one line'
  grep -A2 -B2 'open-decisions.md' "$skill" | grep -qi 'task id'
}

@test "shed SKILL.md's open-decisions step comes before the reporting step" {
  # numbered steps: the open-decisions instruction must appear on an earlier
  # line than the final "Report in three lines" step.
  decisions_line=$(grep -n 'open-decisions.md' "$skill" | head -1 | cut -d: -f1)
  report_line=$(grep -n 'Report in three lines' "$skill" | head -1 | cut -d: -f1)
  [ -n "$decisions_line" ]
  [ -n "$report_line" ]
  [ "$decisions_line" -lt "$report_line" ]
}

@test "shed SKILL.md's existing learnings, NEXT and inbox steps are unchanged" {
  grep -q 'data/learnings.md' "$skill"
  grep -q "NEXT:" "$skill"
  grep -q 'bin/ry-inbox.sh' "$skill"
}

@test "AGENTS.md documents open decisions next to the Learnings section" {
  grep -q '## Learnings' "$agents"
  grep -q 'open-decisions.md' "$agents"
}

@test "AGENTS.md says open decisions are a queue emptied by the dispatcher's answers" {
  grep -A20 'open-decisions.md' "$agents" | grep -qi 'queue'
  grep -A20 'open-decisions.md' "$agents" | grep -qi "dispatcher"
}

@test "AGENTS.md says open decisions are never carried forward untouched" {
  grep -A20 'open-decisions.md' "$agents" | grep -qi 'never'
  grep -A20 'open-decisions.md' "$agents" | grep -qi 'carried forward'
}

@test "shed SKILL.md's safe-to-reset verdict accounts for open decisions" {
  # step 4's "safe to reset" judgment currently only weighs learnings and the
  # inbox; it must also weigh open decisions, or a session could be told safe
  # to reset while a decision it raised sits unrecorded.
  grep -A3 -B3 -i 'safe to reset' "$skill" | grep -qi 'decision'
}
