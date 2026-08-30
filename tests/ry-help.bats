#!/usr/bin/env bats
load helpers

setup() { setup_home; }

@test "every script prints its usage for -h and --help" {
  for f in "$BATS_TEST_DIRNAME"/../bin/ry-*.sh; do
    case $f in *-lib.sh) continue ;; esac
    for flag in -h --help; do
      run bash "$f" "$flag"
      [ "$status" -eq 0 ] || { echo "$f $flag exited $status"; false; }
      [ -n "$output" ] || { echo "$f $flag printed nothing"; false; }
      [[ "$output" == *usage:* ]] || { echo "$f $flag has no usage: line -- $output"; false; }
    done
  done
}

@test "usage comes from the header comment, not a hard-coded line range" {
  run bash "$BATS_TEST_DIRNAME/../bin/ry-dispatch.sh" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"--after"* ]]
  [[ "$output" != *"#"* ]]
  [[ "$output" != *"set -euo"* ]]
}
