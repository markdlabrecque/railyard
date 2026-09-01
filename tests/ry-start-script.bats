#!/usr/bin/env bats
# A project sets up its own freshly cut siding: .railyard/worktree-start.sh
# runs at couple time, after the DDEV name override and before the engine.
# A failure never blocks the dispatch; it becomes an inbox line instead.
load helpers

setup() { setup_home; setup_ddev; make_project xyz; }
teardown() { teardown_tmux; }

wait_for_log() { for _ in $(seq 1 50); do [ -s "$RY_FAKE_CLAUDE_LOG" ] && return; sleep 0.1; done; }

lib() { . "$BATS_TEST_DIRNAME/../bin/ry-lib.sh"; }

startlog() { cat "$RY_HOME/state/$1.start.log"; }
inbox()    { cat "$RY_HOME/state/inbox.md" 2>/dev/null; }

# --- no script: nothing changes ----------------------------------------------

@test "a project with no .railyard/ dispatches exactly as before" {
  run ry-dispatch.sh --haul xyz "x"
  [ "$status" -eq 0 ]
  id=$(sed -n 's/^id=//p' <<<"$output")
  [[ "$output" != *start-script* ]]
  [ "$(cat "$RY_HOME/state/$id.status")" = dispatched ]
  [ ! -f "$RY_HOME/state/$id.start.log" ]
  [ ! -f "$RY_HOME/state/$id.setup-failed.md" ]
  [ ! -f "$RY_HOME/state/events.log" ]
}

# --- success ------------------------------------------------------------------

@test "a start script runs in the siding, and its output is captured" {
  make_start_script xyz <<'EOF'
#!/usr/bin/env bash
echo "cwd=$PWD"
echo "seeded the database"
EOF
  id=$(ry-dispatch.sh --haul xyz "x" | sed -n 's/^id=//p')
  [ "$(cat "$RY_HOME/state/$id.status")" = dispatched ]
  run startlog "$id"
  [[ "$output" == *"seeded the database"* ]]
  [[ "$output" == *"cwd=$RY_HOME/yard/xyz/$id"* ]]
  [ ! -f "$RY_HOME/state/$id.setup-failed.md" ]
  [ ! -s "$RY_HOME/state/inbox.md" ] || [ ! -f "$RY_HOME/state/inbox.md" ]
}

# Handing an executable file with no `#!` to exec is not an error: execvp(3)
# runs it with /bin/sh, which is bash on macOS and dash on Debian and Ubuntu.
# A shebang-less start script would then get a different shell per machine, and
# the first bashism in it would fail on Linux only. So railyard names bash.
@test "a shebang-less script runs under bash, not whatever /bin/sh is" {
  make_start_script xyz <<'EOF'
echo "bash_version=${BASH_VERSION:-none}"
v=RY_PROJECT; echo "indirect=${!v-broken}"
EOF
  id=$(ry-dispatch.sh --haul xyz "x" | sed -n 's/^id=//p')
  run startlog "$id"
  [ ! -f "$RY_HOME/state/$id.setup-failed.md" ]
  [[ "$output" != *bash_version=none* ]]
  [[ "$output" == *indirect=xyz* ]]
}

@test "an executable script's own shebang is honoured" {
  make_start_script xyz <<'EOF'
#!/bin/sh
echo "argv0=$0"
echo "shebang-was-used"
EOF
  id=$(ry-dispatch.sh --haul xyz "x" | sed -n 's/^id=//p')
  run startlog "$id"
  [[ "$output" == *shebang-was-used* ]]
  # Run directly, so argv[0] is the script itself -- not "bash <path>".
  [[ "$output" == *"argv0=$RY_HOME/yard/xyz/$id/.railyard/worktree-start.sh"* ]]
}

@test "a start script with no execute bit still runs" {
  make_start_script xyz --not-executable <<'EOF'
echo ran-anyway
EOF
  id=$(ry-dispatch.sh --haul xyz "x" | sed -n 's/^id=//p')
  [[ "$(startlog "$id")" == *ran-anyway* ]]
}

@test "the engine launches after a successful start script" {
  setup_tmux; make_project abc
  make_start_script abc <<'EOF'
echo fine
EOF
  id=$(ry-dispatch.sh --haul abc "x" | sed -n 's/^id=//p')
  [ "$(cat "$RY_HOME/state/$id.status")" = running ]
}

# --- the environment ----------------------------------------------------------

@test "RY_FIXTURE_PATH is the per-project directory, created when missing" {
  make_start_script xyz <<'EOF'
echo "fixtures=$RY_FIXTURE_PATH"
[ -d "$RY_FIXTURE_PATH" ] && echo fixtures-exists
ls "$RY_FIXTURE_PATH" | wc -l | tr -d ' ' | sed 's/^/entries=/'
EOF
  [ ! -d "$RY_HOME/fixtures" ]
  id=$(ry-dispatch.sh --haul xyz "x" | sed -n 's/^id=//p')
  run startlog "$id"
  [[ "$output" == *"fixtures=$RY_HOME/fixtures/xyz"* ]]
  [[ "$output" == *fixtures-exists* ]]
  [[ "$output" == *entries=0* ]]
  [ -d "$RY_HOME/fixtures/xyz" ]
}

@test "a fixture dropped in fixtures/<project>/ is what the script finds" {
  mkdir -p "$RY_HOME/fixtures/xyz"
  echo "-- not a real dump" > "$RY_HOME/fixtures/xyz/db.sql"
  make_start_script xyz <<'EOF'
cat "$RY_FIXTURE_PATH/db.sql"
EOF
  id=$(ry-dispatch.sh --haul xyz "x" | sed -n 's/^id=//p')
  [[ "$(startlog "$id")" == *"not a real dump"* ]]
}

@test "the script gets the yard vars, the siding and the project" {
  make_start_script xyz <<'EOF'
for v in RY_HOME RY_ID RY_BIN RY_BACKEND RY_SIDING RY_PROJECT RY_FIXTURE_PATH; do
  printf '%s=%s\n' "$v" "${!v-<unset>}"
done
EOF
  id=$(ry-dispatch.sh --haul xyz "x" | sed -n 's/^id=//p')
  run startlog "$id"
  [[ "$output" == *"RY_HOME=$RY_HOME"* ]]
  [[ "$output" == *"RY_ID=$id"* ]]
  [[ "$output" == *"RY_BIN=$(cd "$BATS_TEST_DIRNAME/../bin" && pwd)"* ]]
  [[ "$output" == *"RY_BACKEND=none"* ]]
  [[ "$output" == *"RY_SIDING=$RY_HOME/yard/xyz/$id"* ]]
  [[ "$output" == *"RY_PROJECT=xyz"* ]]
  [[ "$output" != *"<unset>"* ]]
}

# --- ordering against the DDEV override (#2) ----------------------------------

@test "the DDEV name override is already in place when the script runs" {
  make_ddev_project xyz
  make_start_script xyz <<'EOF'
sed -n 's/^name: /ddev-name=/p' .ddev/config.local.yaml
EOF
  id=$(ry-dispatch.sh --haul --prefix 308 xyz "x" | sed -n 's/^id=//p')
  [[ "$(startlog "$id")" == *"ddev-name=308-xyz"* ]]
}

# --- failure ------------------------------------------------------------------

@test "a failing start script still couples, launches, and files an inbox line" {
  make_start_script xyz <<'EOF'
echo "pulling the dump"
echo "no such host" >&2
exit 3
EOF
  run ry-dispatch.sh --haul xyz "x"
  [ "$status" -eq 0 ]
  id=$(sed -n 's/^id=//p' <<<"$output")
  [[ "$output" == *"start-script=failed (exit 3)"* ]]
  [ "$(cat "$RY_HOME/state/$id.status")" = dispatched ]
  run startlog "$id"
  [[ "$output" == *"pulling the dump"* ]]
  [[ "$output" == *"no such host"* ]]
  grep -q "$id start-script-failed exit 3" "$RY_HOME/state/events.log"
  ry-watch.sh --once
  run inbox
  [[ "$output" == *"engine $id start-script-failed: exit 3"* ]]
  [[ "$output" == *"$id.start.log"* ]]
}

@test "the engine is told setup failed, and told not to repair it" {
  make_start_script xyz <<'EOF'
exit 1
EOF
  id=$(ry-dispatch.sh --haul xyz "x" | sed -n 's/^id=//p')
  run cat "$RY_HOME/state/$id.setup-failed.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *".railyard/worktree-start.sh"* ]]
  [[ "$output" == *"exit 1"* ]]
  [[ "$output" == *"not your job"* ]]
  [[ "$output" == *BLOCKED* ]]
}

@test "the failure notice reaches the engine's prompt" {
  setup_tmux; make_project abc
  make_start_script abc <<'EOF'
exit 1
EOF
  id=$(ry-dispatch.sh --haul abc "the task" | sed -n 's/^id=//p')
  [ "$(cat "$RY_HOME/state/$id.status")" = running ]
  wait_for_log
  run cat "$RY_FAKE_CLAUDE_LOG"
  [[ "$output" == *"Setup notice"* ]]
  [[ "$output" == *"the task"* ]]
}

@test "a successful dispatch leaves no setup notice in the prompt" {
  setup_tmux; make_project abc
  make_start_script abc <<'EOF'
echo fine
EOF
  id=$(ry-dispatch.sh --haul abc "the task" | sed -n 's/^id=//p')
  [ -n "$id" ]
  wait_for_log
  run cat "$RY_FAKE_CLAUDE_LOG"
  [[ "$output" != *"Setup notice"* ]]
  [[ "$output" == *"the task"* ]]
}

# --- the timeout --------------------------------------------------------------

@test "a hanging start script is killed at the bound and reported as a timeout" {
  make_start_script xyz <<'EOF'
echo starting
sleep 120
echo never
EOF
  RY_START_TIMEOUT=1 run ry-dispatch.sh --haul xyz "x"
  [ "$status" -eq 0 ]
  id=$(sed -n 's/^id=//p' <<<"$output")
  [[ "$output" == *"start-script=failed (timeout 1s)"* ]]
  [ "$(cat "$RY_HOME/state/$id.status")" = dispatched ]
  run startlog "$id"
  [[ "$output" == *starting* ]]
  [[ "$output" != *never* ]]
  [[ "$output" == *"killed after 1s"* ]]
  # A timeout and a non-zero exit mean different things to whoever debugs it.
  ry-watch.sh --once
  run inbox
  [[ "$output" == *"start-script-failed: timeout 1s"* ]]
  [[ "$output" != *"exit "* ]]
}

@test "the timeout kills the script's children too" {
  make_start_script xyz <<'EOF'
sleep 120 &
echo "child=$!"
wait
EOF
  RY_START_TIMEOUT=1 ry-dispatch.sh --haul xyz "x" >"$BATS_TEST_TMPDIR/out"
  id=$(sed -n 's/^id=//p' "$BATS_TEST_TMPDIR/out")
  child=$(sed -n 's/^child=//p' "$RY_HOME/state/$id.start.log")
  [ -n "$child" ]
  run kill -0 "$child"
  [ "$status" -ne 0 ]
}

# `[ 0 -ge abc ]` errors and stays false, so an unvalidated bound would leave
# the watchdog never firing: the hang the timeout exists to prevent, reachable
# by a typo in an environment variable.
@test "a non-numeric RY_START_TIMEOUT is refused out loud and does not hang" {
  make_start_script xyz <<'EOF'
echo starting
sleep 120
EOF
  for bad in abc 10s -5 0 " "; do
    rm -f "$RY_HOME/state/events.log"
    RY_START_TIMEOUT="$bad" RY_START_TIMEOUT_DEFAULT=1 run ry-dispatch.sh --haul xyz "x"
    [ "$status" -eq 0 ]
    [[ "$output" == *"RY_START_TIMEOUT=$bad"* ]] || { echo "accepted '$bad'"; false; }
    [[ "$output" == *"start-script=failed (timeout 1s)"* ]]
  done
}

@test "an empty RY_START_TIMEOUT falls back to the default without complaint" {
  make_start_script xyz <<'EOF'
sleep 120
EOF
  RY_START_TIMEOUT= RY_START_TIMEOUT_DEFAULT=1 run ry-dispatch.sh --haul xyz "x"
  [ "$status" -eq 0 ]
  [[ "$output" != *"RY_START_TIMEOUT="* ]]
  [[ "$output" == *"start-script=failed (timeout 1s)"* ]]
}

@test "the default bound is 600 seconds" {
  lib
  [ "$RY_START_TIMEOUT_DEFAULT" -eq 600 ]
  grep -q 'RY_START_TIMEOUT:-\$RY_START_TIMEOUT_DEFAULT' "$BATS_TEST_DIRNAME/../bin/ry-lib.sh"
}

# --- the conventional path ----------------------------------------------------

@test "only .railyard/worktree-start.sh is run: no other path is looked at" {
  lib
  [ "$RY_START_SCRIPT" = ".railyard/worktree-start.sh" ]
  mkdir -p "$RY_HOME/projects/xyz/.railway"
  printf 'echo wrong-spelling\n' > "$RY_HOME/projects/xyz/.railway/worktree-start.sh"
  ( cd "$RY_HOME/projects/xyz" && git add -A && git commit -qm railway && git push -q origin HEAD )
  id=$(ry-dispatch.sh --haul xyz "x" | sed -n 's/^id=//p')
  [ ! -f "$RY_HOME/state/$id.start.log" ]
}

# --- surveys ------------------------------------------------------------------

@test "a survey runs the start script too" {
  make_start_script xyz <<'EOF'
echo survey-setup
EOF
  id=$(ry-dispatch.sh --survey xyz "look" | sed -n 's/^id=//p')
  [[ "$(startlog "$id")" == *survey-setup* ]]
}

# --- coupling a queued task ---------------------------------------------------

@test "a task coupled later gets the same treatment" {
  make_start_script xyz <<'EOF'
echo late-setup
EOF
  a=$(ry-dispatch.sh --haul xyz "a" | sed -n 's/^id=//p')
  b=$(ry-dispatch.sh --haul --after "$a" xyz "b" | sed -n 's/^id=//p')
  [ ! -f "$RY_HOME/state/$b.start.log" ]
  run ry-couple.sh "$b"
  [ "$status" -eq 0 ]
  [[ "$(startlog "$b")" == *late-setup* ]]
}
