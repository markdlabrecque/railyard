# Shared bats helpers for railyard.
setup_home() {
  export RY_HOME
  RY_HOME="$(mktemp -d "${BATS_TEST_TMPDIR}/home.XXXX")"
  mkdir -p "$RY_HOME/projects" "$RY_HOME/yard" "$RY_HOME/state"
  export RY_BACKEND=none
  export PATH="$BATS_TEST_DIRNAME/../bin:$PATH"
}

# Create a fake "remote" and clone it into projects/<name> so default-branch
# detection via origin works.
make_project() {
  local name=$1 remote="$BATS_TEST_TMPDIR/remote-$name.git"
  git init -q --bare -b main "$remote"
  git clone -q "$remote" "$RY_HOME/projects/$name" 2>/dev/null
  ( cd "$RY_HOME/projects/$name" &&
    git config user.email t@t && git config user.name t &&
    echo hi > README.md && git add . && git commit -qm init && git push -q origin main )
}
