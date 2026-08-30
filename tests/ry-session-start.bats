#!/usr/bin/env bats
load helpers
setup() { setup_home; }
teardown() {
  pid=$(cat "$RY_HOME/state/.watch.lock" 2>/dev/null); [ -n "$pid" ] && kill "$pid" 2>/dev/null || true
  teardown_tmux
}

# A live pane to hold the yard against.
live_pane() {
  setup_tmux
  tmux -L "$RY_TMUX_SOCKET" new-session -d -s held "sleep 30"
  tmux -L "$RY_TMUX_SOCKET" display -p -t held '#{pane_id}'
}

@test "session start records the pane, starts one watcher, prints a summary" {
  TMUX_PANE=%7 run ry-session-start.sh <<<'{}'
  [ "$status" -eq 0 ]
  [ "$(cat "$RY_HOME/state/yardmaster.pane")" = "%7" ]
  pid=$(cat "$RY_HOME/state/.watch.lock"); kill -0 "$pid"
  [[ "$output" == *"railyard"* ]]
  TMUX_PANE=%7 run ry-session-start.sh <<<'{}'
  [ "$(cat "$RY_HOME/state/.watch.lock")" = "$pid" ]
}

@test "the session that claims the yard is told it is the yardmaster" {
  TMUX_PANE=%7 run ry-session-start.sh <<<'{}'
  [ "$status" -eq 0 ]
  [[ "$output" == *"you are the yardmaster"* ]]
}

@test "reclaiming from the same pane is not a collision" {
  pane=$(live_pane)
  TMUX_PANE=$pane ry-session-start.sh <<<'{}'
  TMUX_PANE=$pane run ry-session-start.sh <<<'{}'
  [ "$status" -eq 0 ]
  [[ "$output" == *"you are the yardmaster"* ]]
  [ "$(cat "$RY_HOME/state/yardmaster.pane")" = "$pane" ]
}

@test "a second session is told another yardmaster holds the yard, and does not steal it" {
  pane=$(live_pane)
  printf '%s\n' "$pane" > "$RY_HOME/state/yardmaster.pane"
  TMUX_PANE=%99 run ry-session-start.sh <<<'{}'
  [ "$status" -eq 0 ]
  [[ "$output" == *"another yardmaster"* ]]
  [[ "$output" == *"$pane"* ]]
  [ "$(cat "$RY_HOME/state/yardmaster.pane")" = "$pane" ]
}

@test "a session takes the yard when the holding pane is gone" {
  setup_tmux
  printf '%s\n' "%404" > "$RY_HOME/state/yardmaster.pane"
  TMUX_PANE=%7 run ry-session-start.sh <<<'{}'
  [ "$status" -eq 0 ]
  [[ "$output" == *"you are the yardmaster"* ]]
  [ "$(cat "$RY_HOME/state/yardmaster.pane")" = "%7" ]
}

@test "session start without tmux still starts the watcher, and says it cannot be woken" {
  run env -u TMUX_PANE ry-session-start.sh <<<'{}'
  [ "$status" -eq 0 ]
  [ ! -e "$RY_HOME/state/yardmaster.pane" ]
  kill -0 "$(cat "$RY_HOME/state/.watch.lock")"
  [[ "$output" == *"cannot wake you"* ]]
}

@test "a session without tmux does not clobber a live claim" {
  pane=$(live_pane)
  printf '%s\n' "$pane" > "$RY_HOME/state/yardmaster.pane"
  run env -u TMUX_PANE ry-session-start.sh <<<'{}'
  [ "$status" -eq 0 ]
  [ "$(cat "$RY_HOME/state/yardmaster.pane")" = "$pane" ]
  [[ "$output" == *"another yardmaster"* ]]
}
