#!/usr/bin/env bats
load helpers
setup() { setup_home; unset RY_ID; }

@test "guard blocks the yardmaster turn while inbox has unread lines" {
  echo 'engine x turn-ended: hi' > "$RY_HOME/state/inbox.md"
  run ry-turnend-guard.sh <<<'{"stop_hook_active":false}'
  [ "$status" -eq 2 ]
  [[ "$output" == *"1 unread"* ]]
}

@test "guard passes with empty inbox" {
  run ry-turnend-guard.sh <<<'{"stop_hook_active":false}'
  [ "$status" -eq 0 ]
}

@test "guard passes when stop_hook_active or when running as an engine" {
  echo 'x' > "$RY_HOME/state/inbox.md"
  run ry-turnend-guard.sh <<<'{"stop_hook_active":true}'
  [ "$status" -eq 0 ]
  RY_ID=some-engine run ry-turnend-guard.sh <<<'{"stop_hook_active":false}'
  [ "$status" -eq 0 ]
}
