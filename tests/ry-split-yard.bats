#!/usr/bin/env bats
load helpers
setup() { setup_home; setup_tmux; setup_herdr; make_project xyz; }
teardown() { teardown_tmux; }

# A task already running under herdr, so a tmux dispatch would split the yard.
herdr_engine() { ry-dispatch.sh --haul xyz "first" | sed -n 's/^id=//p'; }

@test "dispatching on a second backend is refused, and writes no task" {
  herdr_engine >/dev/null
  before=$(ls "$RY_HOME/state" | wc -l)
  setup_tmux
  run ry-dispatch.sh --haul xyz "second"
  [ "$status" -ne 0 ]
  [[ "$output" == *"engines on herdr"* ]]
  [[ "$output" == *"ry-view.sh"* ]]
  [ "$(ls "$RY_HOME/state" | wc -l)" -eq "$before" ]
}

@test "RY_ALLOW_SPLIT overrides the refusal" {
  herdr_engine >/dev/null
  setup_tmux
  RY_ALLOW_SPLIT=1 run ry-dispatch.sh --haul xyz "second"
  [ "$status" -eq 0 ]
}

@test "dispatching on the same backend is not a split" {
  herdr_engine >/dev/null
  run ry-dispatch.sh --haul xyz "second"
  [ "$status" -eq 0 ]
}

@test "the block lifts once the engines on the other backend are decoupled" {
  id=$(herdr_engine)
  ry-decouple.sh --force "$id"
  setup_tmux
  run ry-dispatch.sh --haul xyz "second"
  [ "$status" -eq 0 ]
}

@test "a queued task coupling later is refused too, and its siding is not cut" {
  first=$(herdr_engine)
  second=$(ry-dispatch.sh --haul --after "$first" xyz "second" | sed -n 's/^id=//p')
  setup_tmux
  run ry-couple.sh "$second"
  [ "$status" -ne 0 ]
  [[ "$output" == *"would split it"* ]]
  [ "$(cat "$RY_HOME/state/$second.status")" = queued ]
}

@test "a yard with no engines yet dispatches anywhere" {
  setup_tmux
  run ry-dispatch.sh --haul xyz "first"
  [ "$status" -eq 0 ]
}
