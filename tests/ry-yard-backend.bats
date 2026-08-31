#!/usr/bin/env bats
load helpers
setup() { setup_home; make_project xyz; }
teardown() { teardown_tmux; }

# ry_backend()'s answer, seen the way every caller sees it: the RY_BACKEND the
# yardmaster is started with.
yard_backend() { ry-yard.sh --dry-run | sed -n 's/.*RY_BACKEND=\([a-z]*\).*/\1/p'; }

@test "with no file and no env the yard is tmux" {
  unset RY_BACKEND
  [ "$(yard_backend)" = tmux ]
}

@test "data/yard.md names the backend, so no env var is needed" {
  setup_herdr; unset RY_BACKEND
  register_yard_backend herdr
  [ "$(yard_backend)" = herdr ]
}

@test "the recorded backend is the one a dispatch opens the engine in" {
  setup_herdr; unset RY_BACKEND
  register_yard_backend herdr
  id=$(ry-dispatch.sh --haul xyz "fix it" | sed -n 's/^id=//p')
  grep -q '^backend=herdr$' "$RY_HOME/state/$id.meta"
}

@test "RY_BACKEND still wins over the file" {
  setup_tmux
  register_yard_backend herdr
  [ "$(yard_backend)" = tmux ]
}

@test "an unreadable backend line falls back to tmux" {
  unset RY_BACKEND
  mkdir -p "$RY_HOME/data"
  printf '# This yard\n\nNothing recorded yet.\n' > "$RY_HOME/data/yard.md"
  [ "$(yard_backend)" = tmux ]
}

@test "a bad value in the file is refused, and says where it came from" {
  unset RY_BACKEND
  register_yard_backend zellij
  run ry-yard.sh --dry-run
  [ "$status" -ne 0 ]
  [[ "$output" == *"zellij"* ]]
  [[ "$output" == *"data/yard.md"* ]]
}

@test "a bad value in the env still blames the env" {
  RY_BACKEND=zellij run ry-yard.sh --dry-run
  [ "$status" -ne 0 ]
  [[ "$output" == *"RY_BACKEND"* ]]
  [[ "$output" != *"data/yard.md"* ]]
}
