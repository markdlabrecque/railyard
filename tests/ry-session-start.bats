#!/usr/bin/env bats
load helpers
setup() { setup_home; }
teardown() { pid=$(cat "$RY_HOME/state/.watch.lock" 2>/dev/null); [ -n "$pid" ] && kill "$pid" 2>/dev/null || true; }

@test "session start records the pane, starts one watcher, prints a summary" {
  TMUX_PANE=%7 run ry-session-start.sh <<<'{}'
  [ "$status" -eq 0 ]
  [ "$(cat "$RY_HOME/state/yardmaster.pane")" = "%7" ]
  pid=$(cat "$RY_HOME/state/.watch.lock"); kill -0 "$pid"
  [[ "$output" == *"railyard"* ]]
  TMUX_PANE=%7 run ry-session-start.sh <<<'{}'
  [ "$(cat "$RY_HOME/state/.watch.lock")" = "$pid" ]
}

@test "session start without tmux still starts the watcher" {
  env -u TMUX_PANE ry-session-start.sh <<<'{}'
  [ ! -e "$RY_HOME/state/yardmaster.pane" ]
  kill -0 "$(cat "$RY_HOME/state/.watch.lock")"
}
