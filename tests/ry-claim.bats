#!/usr/bin/env bats
load helpers
setup() { setup_home; setup_tmux; }
teardown() { teardown_tmux; }

@test "show reports an unclaimed yard" {
  run ry-claim.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"unclaimed"* ]]
}

@test "show names the holder, its backend, and whether the terminal is alive" {
  pane=$(live_pane)
  hold_yard tmux "$pane"
  run ry-claim.sh --show
  [ "$status" -eq 0 ]
  [[ "$output" == *"held on tmux by $pane"* ]]
  [[ "$output" == *"alive"* ]]
  hold_yard tmux %404
  run ry-claim.sh --show
  [[ "$output" == *"gone"* ]]
}

@test "show says when this session is the holder" {
  pane=$(live_pane)
  hold_yard tmux "$pane"
  TMUX_PANE=$pane RY_BACKEND=tmux run ry-claim.sh
  [[ "$output" == *"this one"* ]]
}

@test "release drops a claim whose terminal is gone" {
  live_pane >/dev/null   # a live tmux server, but not this pane
  hold_yard tmux %404
  run ry-claim.sh --release
  [ "$status" -eq 0 ]
  [[ "$output" == *"released the yard"* ]]
  [ ! -e "$RY_HOME/state/yardmaster.claim" ]
}

@test "release refuses a live claim, and says how to override" {
  pane=$(live_pane)
  hold_yard tmux "$pane"
  run ry-claim.sh --release
  [ "$status" -ne 0 ]
  [[ "$output" == *"--force"* ]]
  [ "$(claim_target)" = "$pane" ]
}

@test "release --force drops a live claim" {
  pane=$(live_pane)
  hold_yard tmux "$pane"
  run ry-claim.sh --release --force
  [ "$status" -eq 0 ]
  [ ! -e "$RY_HOME/state/yardmaster.claim" ]
}

@test "release on an unclaimed yard is a no-op, not an error" {
  run ry-claim.sh --release
  [ "$status" -eq 0 ]
  [[ "$output" == *"already unclaimed"* ]]
}

@test "take claims the yard for this session, recording its backend" {
  TMUX_PANE=%7 run ry-claim.sh --take
  [ "$status" -eq 0 ]
  [[ "$output" == *"took the yard"* ]]
  [ "$(claim_target)" = "%7" ]
  [ "$(claim_backend)" = "$RY_BACKEND" ]
}

@test "take refuses to steal from a live holder without --force" {
  pane=$(live_pane)
  hold_yard tmux "$pane"
  TMUX_PANE=%99 run ry-claim.sh --take
  [ "$status" -ne 0 ]
  [[ "$output" == *"--force"* ]]
  [ "$(claim_target)" = "$pane" ]
}

@test "take --force steals from a live holder" {
  pane=$(live_pane)
  hold_yard tmux "$pane"
  TMUX_PANE=%99 run ry-claim.sh --take --force
  [ "$status" -eq 0 ]
  [ "$(claim_target)" = "%99" ]
}

@test "take is not a steal when this session already holds the yard" {
  pane=$(live_pane)
  hold_yard tmux "$pane"
  TMUX_PANE=$pane RY_BACKEND=tmux run ry-claim.sh --take
  [ "$status" -eq 0 ]
  [ "$(claim_target)" = "$pane" ]
}

@test "take across backends records the new backend, and takes a dead claim freely" {
  live_pane >/dev/null
  setup_herdr
  hold_yard tmux %404
  HERDR_PANE_ID=pane-new run ry-claim.sh --take
  [ "$status" -eq 0 ]
  [ "$(claim_backend)" = herdr ]
  [ "$(claim_target)" = pane-new ]
}

@test "take refuses when this session has no terminal" {
  run env -u TMUX_PANE -u CMUX_WORKSPACE_ID -u HERDR_PANE_ID -u ORCA_TERMINAL_HANDLE \
    ry-claim.sh --take
  [ "$status" -ne 0 ]
  [[ "$output" == *"no"*"terminal"* ]]
  [[ "$output" == *"--force does not cover this"* ]]
}

@test "take names the backend mismatch when the session is a terminal of another kind" {
  run env -u TMUX_PANE -u ORCA_TERMINAL_HANDLE -u HERDR_PANE_ID CMUX_WORKSPACE_ID=ws-1 ry-claim.sh --take
  [ "$status" -ne 0 ]
  [[ "$output" == *"says tmux"* ]]
  [[ "$output" == *"this session is a cmux terminal"* ]]
  [[ "$output" == *"--force does not cover this"* ]]
}

@test "--force does not get past a backend mismatch" {
  run env -u TMUX_PANE -u ORCA_TERMINAL_HANDLE -u HERDR_PANE_ID CMUX_WORKSPACE_ID=ws-1 ry-claim.sh --take --force
  [ "$status" -ne 0 ]
  [[ "$output" == *"this session is a cmux terminal"* ]]
}

@test "an unknown option is refused" {
  run ry-claim.sh --steal
  [ "$status" -ne 0 ]
}

@test "a pane that is gone reads as gone even while its tmux server runs" {
  pane=$(live_pane)
  hold_yard tmux "$pane"
  run ry-claim.sh --show
  [[ "$output" == *"alive"* ]]
  tmux -L "$RY_TMUX_SOCKET" kill-session -t held
  run ry-claim.sh --show
  [[ "$output" == *"gone"* ]]
  run ry-claim.sh --release
  [ "$status" -eq 0 ]
}

@test "--held is an exit code and nothing else" {
  pane=$(live_pane)
  hold_yard tmux "$pane"
  run ry-claim.sh --held
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "--held exits 1 on an unclaimed yard" {
  run ry-claim.sh --held
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "--held exits 1 when the holding terminal has closed" {
  live_pane >/dev/null
  hold_yard tmux %404
  run ry-claim.sh --held
  [ "$status" -eq 1 ]
}

@test "--json names the backend, the target and whether it is alive" {
  pane=$(live_pane)
  hold_yard tmux "$pane"
  run ry-claim.sh --json
  [ "$status" -eq 0 ]
  [ "$(jq -r '.held' <<<"$output")" = true ]
  [ "$(jq -r '.backend' <<<"$output")" = tmux ]
  [ "$(jq -r '.target' <<<"$output")" = "$pane" ]
  [ "$(jq -r '.alive' <<<"$output")" = true ]
}

@test "--json on an unclaimed yard is held false with null fields" {
  run ry-claim.sh --json
  [ "$status" -eq 0 ]
  [ "$(jq -r '.held' <<<"$output")" = false ]
  [ "$(jq -r '.backend' <<<"$output")" = null ]
  [ "$(jq -r '.target' <<<"$output")" = null ]
  [ "$(jq -r '.alive' <<<"$output")" = false ]
}

@test "--json reports a claim whose terminal has closed as held but not alive" {
  live_pane >/dev/null
  hold_yard herdr pane-gone
  run ry-claim.sh --json
  [ "$(jq -r '.held' <<<"$output")" = true ]
  [ "$(jq -r '.backend' <<<"$output")" = herdr ]
  [ "$(jq -r '.alive' <<<"$output")" = false ]
}
