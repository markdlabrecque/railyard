#!/usr/bin/env bats
load helpers
setup() { setup_home; setup_tmux; }
teardown() {
  pid=$(cat "$RY_HOME/state/.watch.lock" 2>/dev/null); [ -n "$pid" ] && kill "$pid" 2>/dev/null || true
  teardown_tmux
}

@test "session start records the pane, starts one watcher, prints a summary" {
  TMUX_PANE=%7 run ry-session-start.sh <<<'{}'
  [ "$status" -eq 0 ]
  [ "$(claim_target)" = "%7" ]
  pid=$(cat "$RY_HOME/state/.watch.lock"); kill -0 "$pid"
  [[ "$output" == *"railyard"* ]]
  TMUX_PANE=%7 run ry-session-start.sh <<<'{}'
  [ "$(cat "$RY_HOME/state/.watch.lock")" = "$pid" ]
}

@test "the session that claims the yard is told it is the yardmaster" {
  TMUX_PANE=%7 run ry-session-start.sh <<<'{}'
  [ "$status" -eq 0 ]
  [[ "$output" == *"you are the yardmaster"* ]]
  # nothing to take: the take line belongs only to a session that stood down
  [[ "$output" != *"ry-claim.sh"* ]]
}

@test "reclaiming from the same pane is not a collision" {
  pane=$(live_pane)
  TMUX_PANE=$pane ry-session-start.sh <<<'{}'
  TMUX_PANE=$pane run ry-session-start.sh <<<'{}'
  [ "$status" -eq 0 ]
  [[ "$output" == *"you are the yardmaster"* ]]
  [ "$(claim_target)" = "$pane" ]
}

@test "a second session is told another yardmaster holds the yard, and does not steal it" {
  pane=$(live_pane)
  hold_yard "$RY_BACKEND" "$pane"
  TMUX_PANE=%99 run ry-session-start.sh <<<'{}'
  [ "$status" -eq 0 ]
  [[ "$output" == *"another yardmaster"* ]]
  [[ "$output" == *"$pane"* ]]
  # a stood-down session is handed the one command that could change its standing
  [[ "$output" == *"bin/ry-claim.sh --take --force"* ]]
  [ "$(claim_target)" = "$pane" ]
}

@test "a session takes the yard when the holding pane is gone" {
  hold_yard "$RY_BACKEND" "%404"
  TMUX_PANE=%7 run ry-session-start.sh <<<'{}'
  [ "$status" -eq 0 ]
  [[ "$output" == *"you are the yardmaster"* ]]
  [ "$(claim_target)" = "%7" ]
}

@test "session start without tmux still starts the watcher, and says it cannot be woken" {
  run env -u TMUX_PANE ry-session-start.sh <<<'{}'
  [ "$status" -eq 0 ]
  [ ! -e "$RY_HOME/state/yardmaster.claim" ]
  kill -0 "$(cat "$RY_HOME/state/.watch.lock")"
  [[ "$output" == *"cannot wake you"* ]]
}

@test "a session without tmux does not clobber a live claim" {
  pane=$(live_pane)
  hold_yard "$RY_BACKEND" "$pane"
  run env -u TMUX_PANE ry-session-start.sh <<<'{}'
  [ "$status" -eq 0 ]
  [ "$(claim_target)" = "$pane" ]
  [[ "$output" == *"another yardmaster"* ]]
}

@test "a session on another backend is told the yard is held elsewhere" {
  pane=$(live_pane)
  hold_yard tmux "$pane"
  RY_BACKEND=orca ORCA_TERMINAL_HANDLE=term_x run ry-session-start.sh <<<'{}'
  [ "$status" -eq 0 ]
  [[ "$output" == *"holds the yard on the tmux backend"* ]]
  [[ "$output" == *"bin/ry-claim.sh --take --force"* ]]
  [ "$(claim_backend)" = tmux ]
  [ "$(claim_target)" = "$pane" ]
}

@test "claiming the yard clears the per-backend files it replaced" {
  printf 'stale\n' > "$RY_HOME/state/yardmaster.pane"
  printf 'stale\n' > "$RY_HOME/state/yardmaster.orca"
  TMUX_PANE=%7 run ry-session-start.sh <<<'{}'
  [ "$status" -eq 0 ]
  [ ! -e "$RY_HOME/state/yardmaster.pane" ]
  [ ! -e "$RY_HOME/state/yardmaster.orca" ]
  [ "$(claim_target)" = "%7" ]
}

# data/learnings.md is a queue, not an archive: /shed files into it, and the
# next session start, /manifest or /allaboard empties it by promoting or
# dropping each line. So the summary has to say when it is not empty.
@test "session start reports unprocessed learnings" {
  mkdir -p "$RY_HOME/data"
  printf '# Learnings\n\n- 2026-08-30 — one\n- 2026-08-30 — two\n' > "$RY_HOME/data/learnings.md"
  TMUX_PANE=%7 run ry-session-start.sh <<<'{}'
  [ "$status" -eq 0 ]
  [[ "$output" == *"2 unfiled learning(s)"* ]]
}

@test "an empty or header-only learnings file is not reported" {
  TMUX_PANE=%7 run ry-session-start.sh <<<'{}'
  [[ "$output" != *"unfiled learning"* ]]
  mkdir -p "$RY_HOME/data"; printf '# Learnings\n' > "$RY_HOME/data/learnings.md"
  TMUX_PANE=%7 run ry-session-start.sh <<<'{}'
  [[ "$output" != *"unfiled learning"* ]]
}

@test "an engine stands down: no claim, no watcher, no summary" {
  RY_ID=proj-0101-0000-abcd TMUX_PANE=%7 run ry-session-start.sh <<<'{}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -f "$RY_HOME/state/yardmaster.claim" ]
  [ ! -f "$RY_HOME/state/.watch.lock" ]
}

@test "an engine does not take a yard another terminal holds" {
  pane=$(live_pane)
  hold_yard "$RY_BACKEND" "$pane"
  RY_ID=proj-0101-0000-abcd TMUX_PANE=%99 run ry-session-start.sh <<<'{}'
  [ "$status" -eq 0 ]
  [ "$(claim_target)" = "$pane" ]
}

# data/yard.md and data/projects.md are machine-local and gitignored, so a
# fresh clone has neither and the readers quietly fall back to a tmux yard with
# no projects. The first session in such a clone says so once.
@test "a fresh clone is told it has no yard config yet" {
  git init -q "$RY_HOME"
  TMUX_PANE=%7 run ry-session-start.sh <<<'{}'
  [ "$status" -eq 0 ]
  [[ "$output" == *"First run"* ]]
  [[ "$output" == *"data/yard.md"* ]]
  [[ "$output" == *"you are the yardmaster"* ]]
}

@test "a configured yard gets no first-run notice, and neither does a non-clone" {
  git init -q "$RY_HOME"
  mkdir -p "$RY_HOME/data"; printf -- '- `backend: tmux`\n' > "$RY_HOME/data/yard.md"
  TMUX_PANE=%7 run ry-session-start.sh <<<'{}'
  [[ "$output" != *"First run"* ]]
  rm "$RY_HOME/data/yard.md"; register_project demo local-only
  TMUX_PANE=%7 run ry-session-start.sh <<<'{}'
  [[ "$output" != *"First run"* ]]
  rm -rf "$RY_HOME/data" "$RY_HOME/.git"
  TMUX_PANE=%7 run ry-session-start.sh <<<'{}'
  [[ "$output" != *"First run"* ]]
}

# Regression guard for the hermetic environment established in tests/helpers.bash.
# Inside an engine siding RY_ID and friends are exported into the terminal;
# without the unset at load time this test fails, and so do the eleven tests
# above it that drive session start through the real script.
# RY_HOME and RY_BACKEND are not checked: setup_home always overwrites them.
@test "the suite runs with no ambient yard environment" {
  [ -z "${RY_ID:-}" ]
  [ -z "${RY_BIN:-}" ]
}
