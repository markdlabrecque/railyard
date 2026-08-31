#!/usr/bin/env bats
# Railyard is developed on macOS and has to run on Linux. These are the two
# places where the same command name means different things on each.
load helpers
setup() { setup_home; }

lib() { . "$BATS_TEST_DIRNAME/../bin/ry-lib.sh"; }

@test "ry_mtime reads an mtime natively" {
  lib
  touch "$RY_HOME/f"
  run ry_mtime "$RY_HOME/f"
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]+$ ]]
  [ "$output" -gt 1700000000 ]
}

# GNU stat accepts `-f` as --file-system and exits 0 on an unknown directive,
# so asking BSD-first returns a placeholder that never triggers the fallback.
@test "ry_mtime asks GNU stat first, so a GNU box never sees the -f placeholder" {
  lib
  PATH="$BATS_TEST_DIRNAME/fakebin-gnu:$PATH"
  run ry_mtime "$RY_HOME/anything"
  [ "$status" -eq 0 ]
  [ "$output" = 1700000000 ]
}

@test "ry_mtime still falls back to BSD stat, which refuses -c cleanly" {
  lib
  PATH="$BATS_TEST_DIRNAME/fakebin-bsd:$PATH"
  run ry_mtime "$RY_HOME/anything"
  [ "$status" -eq 0 ]
  [ "$output" = 1600000000 ]
}

@test "ry_require names the missing tool and how to install it" {
  lib
  run ry_require definitely-not-installed
  [ "$status" -ne 0 ]
  [[ "$output" == *"definitely-not-installed"* ]]
  [[ "$output" == *"install"* ]]
}

@test "ry_require passes when every tool is there, and checks all of them" {
  lib
  run ry_require git; [ "$status" -eq 0 ]
  run ry_require git definitely-not-installed
  [ "$status" -ne 0 ]
  [[ "$output" == *"definitely-not-installed"* ]]
}
