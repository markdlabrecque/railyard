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
