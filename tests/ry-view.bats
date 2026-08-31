#!/usr/bin/env bats
load helpers
setup() { setup_home; setup_tmux; }
teardown() { teardown_tmux; }

# A yard hosted in tmux: the session ry-view.sh attaches viewers to.
yard_session() { tmux -L "$RY_TMUX_SOCKET" new-session -d -s "$(tmux_session_name)" -n yard "sleep 30"; }
tmux_session_name() { printf '%s\n' "${RY_TMUX_SESSION:-railyard}"; }

@test "a backend is required" {
  yard_session
  run ry-view.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"which backend"* ]]
}

@test "an unknown backend is refused" {
  yard_session
  run ry-view.sh screen
  [ "$status" -ne 0 ]
}

@test "tmux is refused: it hosts the yard, it does not view it" {
  yard_session
  run ry-view.sh tmux
  [ "$status" -ne 0 ]
  [[ "$output" == *"ry-yard.sh"* ]]
}

@test "a yard that is not running in tmux has nothing to look at" {
  run ry-view.sh herdr
  [ "$status" -ne 0 ]
  [[ "$output" == *"no tmux yard"* ]]
}

@test "--dry-run prints the attach command and opens nothing" {
  yard_session
  setup_herdr
  run ry-view.sh --dry-run herdr
  [ "$status" -eq 0 ]
  [[ "$output" == *"tmux -L $RY_TMUX_SOCKET new-session -t railyard -s railyard-herdr"* ]]
  [ ! -s "$RY_FAKE_HERDR_LOG" ]
}

@test "herdr opens one tab on the yard running the attach command" {
  yard_session
  setup_herdr
  RY_BACKEND=none run ry-view.sh herdr
  [ "$status" -eq 0 ]
  grep -q -- "tab create --cwd $RY_HOME --label railyard-view" "$RY_FAKE_HERDR_LOG"
  grep -q -- "pane run pane-fake-.*new-session -t railyard -s railyard-herdr" "$RY_FAKE_HERDR_LOG"
}

@test "cmux opens one workspace running the attach command" {
  yard_session
  setup_cmux
  RY_BACKEND=none run ry-view.sh cmux
  [ "$status" -eq 0 ]
  grep -q -- "new-workspace --name railyard-view --cwd $RY_HOME --command .*new-session -t railyard -s railyard-cmux" "$RY_FAKE_CMUX_LOG"
}

@test "orca registers the yard as a repo and opens one terminal on it" {
  yard_session
  setup_orca
  RY_BACKEND=none run ry-view.sh orca
  [ "$status" -eq 0 ]
  grep -q -- "repo add --path $RY_HOME" "$RY_FAKE_ORCA_LOG"
  grep -q -- "terminal create --worktree path:$RY_HOME --title railyard-view --command .*new-session -t railyard -s railyard-orca" "$RY_FAKE_ORCA_LOG"
}

@test "a viewer is not an engine: no task state is written, and the claim is untouched" {
  yard_session
  hold_yard tmux %1
  setup_herdr
  run ry-view.sh herdr
  [ "$status" -eq 0 ]
  [ -z "$(ls -A "$RY_HOME/state" | grep -v yardmaster.claim)" ]
  [ "$(claim_target)" = "%1" ]
  [ "$(claim_backend)" = tmux ]
}

@test "a second viewer on the same backend gets its own session name" {
  yard_session
  tmux -L "$RY_TMUX_SOCKET" new-session -d -t railyard -s railyard-herdr
  setup_herdr
  run ry-view.sh --dry-run herdr
  [ "$status" -eq 0 ]
  [[ "$output" == *"-s railyard-herdr-2"* ]]
}

@test "the viewer session is cleaned up when the viewer detaches" {
  yard_session
  setup_herdr
  run ry-view.sh --dry-run herdr
  [[ "$output" == *"kill-session -t railyard-herdr"* ]]
}

@test "RY_TMUX_SESSION names the yard the viewer attaches to" {
  export RY_TMUX_SESSION=second
  yard_session
  setup_herdr
  run ry-view.sh --dry-run herdr
  [ "$status" -eq 0 ]
  [[ "$output" == *"new-session -t second -s second-herdr"* ]]
}
