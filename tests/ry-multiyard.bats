#!/usr/bin/env bats
load helpers

setup() { setup_home; setup_tmux; make_project xyz; }
teardown() { teardown_tmux; }

env_of() { bash -c ". '$BATS_TEST_DIRNAME/../bin/ry-lib.sh'; ry_env_exports"; }

@test "the child environment always carries RY_HOME" {
  run env_of
  [ "$status" -eq 0 ]
  [[ "$output" == *"RY_HOME=$RY_HOME"* ]]
}

@test "the child environment carries the tmux session and socket when set" {
  RY_TMUX_SESSION=beta run env_of
  [[ "$output" == *"RY_TMUX_SESSION=beta"* ]]
  [[ "$output" == *"RY_TMUX_SOCKET=$RY_TMUX_SOCKET"* ]]
}

@test "the child environment omits tmux vars that are not set" {
  run env -u RY_TMUX_SESSION -u RY_TMUX_SOCKET bash -c \
    ". '$BATS_TEST_DIRNAME/../bin/ry-lib.sh'; ry_env_exports"
  [ "$status" -eq 0 ]
  [[ "$output" != *RY_TMUX_SESSION* ]]
  [[ "$output" != *RY_TMUX_SOCKET* ]]
}

@test "a value with spaces survives the trip" {
  RY_TMUX_SESSION='two words' run env_of
  [[ "$output" == *"RY_TMUX_SESSION="* ]]
  eval "export $output"
  [ "$RY_TMUX_SESSION" = "two words" ]
}

@test "the yard session it opens carries its own session name" {
  RY_TMUX_SESSION=beta ry-yard.sh --dry-run > "$BATS_TEST_TMPDIR/cmd"
  grep -q "RY_TMUX_SESSION=beta" "$BATS_TEST_TMPDIR/cmd"
  grep -q "RY_HOME=" "$BATS_TEST_TMPDIR/cmd"
}

@test "a second yard opens its engine windows in its own tmux session" {
  RY_TMUX_SESSION=beta run ry-dispatch.sh --haul xyz "beta work"
  [ "$status" -eq 0 ]
  id=$(sed -n 's/^id=//p' <<<"$output")
  tmux -L "$RY_TMUX_SOCKET" list-windows -t beta -F '#W' | grep -qx "ry-$id"
  ! tmux -L "$RY_TMUX_SOCKET" has-session -t "=railyard" 2>/dev/null
}
