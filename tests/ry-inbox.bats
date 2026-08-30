#!/usr/bin/env bats
load helpers
setup() { setup_home; }

@test "inbox prints unread lines and --ack archives them" {
  printf 'a\nb\n' > "$RY_HOME/state/inbox.md"
  run ry-inbox.sh
  [ "$status" -eq 0 ]; [ "$output" = $'a\nb' ]
  run ry-inbox.sh --ack
  [ "$status" -eq 0 ]
  [ ! -s "$RY_HOME/state/inbox.md" ]
  grep -q '^b$' "$RY_HOME/state/inbox.archive.log"
}

@test "inbox is quiet when empty" {
  run ry-inbox.sh
  [ "$status" -eq 0 ]; [ -z "$output" ]
}
