# Shared bats helpers for railyard.

# Hermetic environment. Engines export RY_ID, RY_HOME, RY_BIN and RY_BACKEND
# into their terminal, and bin/ry-session-start.sh correctly stands down when
# RY_ID is set — so a suite that inherits an engine's environment tests the
# stand-down path instead of the behaviour it asserts. This runs at `load`
# time, which is the only seam every test file must pass through: `load
# helpers` precedes setup(), so it lands before any test body, and a new file
# cannot forget it the way it could forget setup_home. Tests that need these
# variables set them themselves, per command.
unset RY_ID RY_HOME RY_BIN RY_BACKEND
setup_home() {
  export RY_HOME
  RY_HOME="$(mktemp -d "${BATS_TEST_TMPDIR}/home.XXXX")"
  mkdir -p "$RY_HOME/projects" "$RY_HOME/yard" "$RY_HOME/state"
  export RY_BACKEND=none
  export RY_CLAUDE_JSON="$BATS_TEST_TMPDIR/claude.json"
  export PATH="$BATS_TEST_DIRNAME/../bin:$PATH"
}

# Create a fake "remote" and clone it into projects/<name> so default-branch
# detection via origin works.
make_project() {
  local name=$1 remote
  remote="$BATS_TEST_TMPDIR/remote-$name.git"
  git init -q --bare -b main "$remote"
  git clone -q "$remote" "$RY_HOME/projects/$name" 2>/dev/null
  ( cd "$RY_HOME/projects/$name" &&
    git config user.email t@t && git config user.name t &&
    echo hi > README.md && git add . && git commit -qm init && git push -q origin main )
}

# tmux on a private socket so tests never touch the user's server.
setup_tmux() {
  export RY_TMUX_SOCKET="ry-test-$$-$RANDOM"
  export RY_BACKEND=tmux
  export RY_FAKE_CLAUDE_LOG="$BATS_TEST_TMPDIR/claude.log"
  export PATH="$BATS_TEST_DIRNAME/fakebin:$PATH"
}
teardown_tmux() { tmux -L "$RY_TMUX_SOCKET" kill-server 2>/dev/null || true; }

# A live pane to hold the yard against. Needs setup_tmux to have run in the
# test itself: called from $(...) it would set the private socket in a subshell
# and the test would go on to talk to the user's own tmux server.
live_pane() {
  tmux -L "$RY_TMUX_SOCKET" new-session -d -s held "sleep 30"
  tmux -L "$RY_TMUX_SOCKET" display -p -t held '#{pane_id}'
}

# Add a branch to a project's fake remote (and fetch it into the clone).
make_branch() {
  local name=$1 branch=$2 dir
  dir="$RY_HOME/projects/$name"
  ( cd "$dir" && git push -q origin "HEAD:refs/heads/$branch" && git fetch -q origin )
}

# Register a project line in data/projects.md.
register_project() {  # <name> <mode> [base]
  local name=$1 mode=$2 base=${3:-}
  mkdir -p "$RY_HOME/data"
  if [ -n "$base" ]; then
    printf -- '- `%s` — %s, base: %s, notes: test\n' "$name" "$mode" "$base" >> "$RY_HOME/data/projects.md"
  else
    printf -- '- `%s` — %s, notes: test\n' "$name" "$mode" >> "$RY_HOME/data/projects.md"
  fi
}

# Add a commit straight onto the project's fake remote, behind the clone's back.
remote_commit() {  # <project> <branch> <message>
  local name=$1 branch=$2 msg=$3 remote tmp
  remote="$BATS_TEST_TMPDIR/remote-$name.git"
  tmp=$(mktemp -d "$BATS_TEST_TMPDIR/rc.XXXX")
  git clone -q --branch "$branch" "$remote" "$tmp"
  ( cd "$tmp" && git config user.email t@t && git config user.name t &&
    echo "$msg" >> remote.txt && git add . && git commit -qm "$msg" &&
    git push -q origin "$branch" )
  rm -rf "$tmp"
}

# Commit in the project clone without pushing (simulates a local-only merge).
local_commit() {  # <project> <message>
  local name=$1 msg=$2 dir
  dir="$RY_HOME/projects/$name"
  ( cd "$dir" && echo "$msg" >> local.txt && git add . && git commit -qm "$msg" )
}

# cmux backend: fake CLI plus the state files it reads.
setup_cmux() {
  export RY_BACKEND=cmux
  export RY_FAKE_CMUX_LOG="$BATS_TEST_TMPDIR/cmux.log" RY_FAKE_CMUX_WS="$BATS_TEST_TMPDIR/cmux-ws"
  : > "$RY_FAKE_CMUX_WS"
  export PATH="$BATS_TEST_DIRNAME/fakebin:$PATH"
}

setup_orca() {
  export RY_BACKEND=orca
  export RY_FAKE_ORCA_LOG="$BATS_TEST_TMPDIR/orca.log" RY_FAKE_ORCA_REPOS="$BATS_TEST_TMPDIR/orca-repos.json"
  export RY_FAKE_ORCA_WORKTREES="$BATS_TEST_TMPDIR/orca-worktrees.txt"
  export RY_FAKE_ORCA_CREATE_COUNTER="$BATS_TEST_TMPDIR/orca-create-counter"
  rm -f "$RY_FAKE_ORCA_CREATE_COUNTER"
  # Real orca's retry sleep is a few real seconds; tests never wait for it.
  export RY_ORCA_RETRY_SLEEP=0
  export PATH="$BATS_TEST_DIRNAME/fakebin:$PATH"
}

# herdr backend: fake CLI plus the state file it reads.
setup_herdr() {
  export RY_BACKEND=herdr
  export RY_FAKE_HERDR_LOG="$BATS_TEST_TMPDIR/herdr.log" RY_FAKE_HERDR_TABS="$BATS_TEST_TMPDIR/herdr-tabs"
  export RY_FAKE_HERDR_BLOCKED="$BATS_TEST_TMPDIR/herdr-blocked"
  : > "$RY_FAKE_HERDR_TABS"; : > "$RY_FAKE_HERDR_BLOCKED"
  export PATH="$BATS_TEST_DIRNAME/fakebin:$PATH"
}

# The yard claim: one file, `backend=` and `target=`.
claim_target() { sed -n 's/^target=//p' "$RY_HOME/state/yardmaster.claim" 2>/dev/null; }
claim_backend() { sed -n 's/^backend=//p' "$RY_HOME/state/yardmaster.claim" 2>/dev/null; }
hold_yard() {  # <backend> <target>
  printf 'backend=%s\ntarget=%s\n' "$1" "$2" > "$RY_HOME/state/yardmaster.claim"
}

# Record the yard's default backend in data/yard.md.
register_yard_backend() {  # <backend>
  mkdir -p "$RY_HOME/data"
  printf '# This yard\n\n- `backend: %s`\n' "$1" > "$RY_HOME/data/yard.md"
}

# ddev: fake CLI plus the log it writes.
setup_ddev() {
  export RY_FAKE_DDEV_LOG="$BATS_TEST_TMPDIR/ddev.log"
  : > "$RY_FAKE_DDEV_LOG"
  export PATH="$BATS_TEST_DIRNAME/fakebin:$PATH"
}

# Turn a project into a DDEV project: a .ddev/ directory, and the gitignore
# line every real project has.
make_ddev_project() {  # <name> [--tracked]
  local name=$1 dir
  dir="$RY_HOME/projects/$name"
  mkdir -p "$dir/.ddev"
  printf 'name: %s\n' "$name" > "$dir/.ddev/config.yaml"
  if [ "${2:-}" = --tracked ]; then
    # Actually tracked: committed, with no ignore rule. Anything less tests
    # "not ignored", which is a different thing from "the project tracks it".
    printf 'name: committed-by-the-project\n' > "$dir/.ddev/config.local.yaml"
  else
    printf '/.ddev/config.local.yaml\n' > "$dir/.gitignore"
  fi
  ( cd "$dir" && git add -A && git commit -qm ddev && git push -q origin HEAD )
}

# Commit a .railyard/worktree-start.sh into a project, so every siding cut from
# it has one. Body is read from stdin.
make_start_script() {  # <project> [--not-executable]  <<'EOF' ... EOF
  local name=$1 dir
  dir="$RY_HOME/projects/$name"
  mkdir -p "$dir/.railyard"
  cat > "$dir/.railyard/worktree-start.sh"
  [ "${2:-}" = --not-executable ] || chmod +x "$dir/.railyard/worktree-start.sh"
  ( cd "$dir" && git add -A && git commit -qm start-script && git push -q origin HEAD )
}
