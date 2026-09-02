#!/usr/bin/env bats
# Every siding of a DDEV project gets its own DDEV project name, written at
# couple time and torn down at decouple.
load helpers

setup() { setup_home; setup_ddev; make_project xyz; }

lib() { . "$BATS_TEST_DIRNAME/../bin/ry-lib.sh"; }

# --- prefix ------------------------------------------------------------------

@test "--prefix is recorded in the task's meta" {
  id=$(ry-dispatch.sh --haul --prefix 308 xyz "x" | sed -n 's/^id=//p')
  grep -q '^prefix=308$' "$RY_HOME/state/$id.meta"
}

@test "a bad --prefix is refused at dispatch time, naming the value" {
  for bad in "two words" "-lead" "has_underscore" "" ; do
    run ry-dispatch.sh --haul --prefix "$bad" xyz "x"
    [ "$status" -ne 0 ] || { echo "accepted '$bad'"; false; }
    [[ "$output" == *"--prefix"* ]]
  done
  [ -z "$(ls "$RY_HOME/state")" ]
}

@test "a bad --prefix is refused before any track is laid" {
  run ry-dispatch.sh --haul --prefix "no good" xyz "x"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no good"* ]]
  [ -z "$(ls "$RY_HOME/yard")" ]
}

@test "ry_prefix_valid accepts a ticket number and a single word" {
  lib
  run ry_prefix_valid 308;      [ "$status" -eq 0 ]
  run ry_prefix_valid ddev;     [ "$status" -eq 0 ]
  run ry_prefix_valid A1;       [ "$status" -eq 0 ]
  run ry_prefix_valid "a b";    [ "$status" -ne 0 ]
  run ry_prefix_valid "-a";     [ "$status" -ne 0 ]
  run ry_prefix_valid "a.b";    [ "$status" -ne 0 ]
}

# Every prefix a dispatcher has typed by hand was 3-5 characters; the cap is
# there to stop the default from being the one that runs long (#36).
@test "ry_prefix_valid caps a prefix at 6 characters" {
  lib
  run ry_prefix_valid 123456;   [ "$status" -eq 0 ]
  run ry_prefix_valid ns-297;   [ "$status" -eq 0 ]
  run ry_prefix_valid 1234567;  [ "$status" -ne 0 ]
  run ry_prefix_valid ddev-fix; [ "$status" -ne 0 ]
}

@test "an over-long --prefix is refused at dispatch, naming the cap and the length" {
  make_ddev_project xyz
  run ry-dispatch.sh --haul --prefix 1234567 xyz "x"
  [ "$status" -ne 0 ]
  [[ "$output" == *"--prefix"* ]]
  [[ "$output" == *"1234567"* ]]
  [[ "$output" == *" 6 "* ]]                    # the cap
  [[ "$output" == *" 7"* ]]                     # the length it got
  [ -z "$(ls "$RY_HOME/state")" ]
  [ -z "$(ls "$RY_HOME/yard")" ]
}

@test "a 6-character --prefix is accepted and recorded" {
  make_ddev_project xyz
  id=$(ry-dispatch.sh --haul --prefix 123456 xyz "x" | sed -n 's/^id=//p')
  grep -q '^prefix=123456$' "$RY_HOME/state/$id.meta"
  grep -q '^name: 123456-xyz$' "$RY_HOME/yard/xyz/$id/.ddev/config.local.yaml"
}

# The default is a digest of the id, not the id: the id ran to 21 characters
# in `ddev list` (#36). Not a substring of the id either, or it would be a
# truncation, and two tasks on one ticket truncate to the same thing.
@test "without --prefix a 6-character digest of the id is used" {
  make_ddev_project xyz
  id=$(ry-dispatch.sh --haul --slug "news filter styling" xyz "x" | sed -n 's/^id=//p')
  prefix=$(sed -n 's/^prefix=//p' "$RY_HOME/state/$id.meta")
  [ "${#prefix}" -eq 6 ]
  [[ "$prefix" =~ ^[0-9a-f]{6}$ ]]
  [[ "$id" != *"$prefix"* ]]
  grep -q "^name: $prefix-xyz\$" "$RY_HOME/yard/xyz/$id/.ddev/config.local.yaml"
}

@test "two ids sharing their first 6 characters get different default prefixes" {
  lib
  a=$(ry_ddev_default_prefix 297-news-filter-no-scroll-jump)
  b=$(ry_ddev_default_prefix 297-news-listing-spacing-revision)
  [ "${#a}" -eq 6 ] && [ "${#b}" -eq 6 ]
  [ "$a" != "$b" ]
}

@test "the default prefix is deterministic: the same id always gives the same 6 characters" {
  lib
  a=$(ry_ddev_default_prefix latest-commit-on-main)
  b=$(ry_ddev_default_prefix latest-commit-on-main)
  [ "$a" = "$b" ]
  [ "${#a}" -eq 6 ]
  # and dispatch records exactly what the library computes from the id alone
  make_ddev_project xyz
  id=$(ry-dispatch.sh --haul --slug "latest commit on main" xyz "x" | sed -n 's/^id=//p')
  grep -q "^prefix=$(ry_ddev_default_prefix "$id")\$" "$RY_HOME/state/$id.meta"
}

# --- the name ----------------------------------------------------------------

@test "ry_ddev_name joins prefix and project" {
  lib
  run ry_ddev_name 3a8d island-health
  [ "$status" -eq 0 ]
  [ "$output" = "3a8d-island-health" ]
}

# The prefix is capped at dispatch; the project name has no limit, by decision
# (#36). So the name has no length branch left, and there is no "too long"
# fallback for dispatch to take: an over-long prefix never gets this far.
@test "ry_ddev_name has no length limit: an 80-character project name is joined as is" {
  lib
  long_project=$(printf 'p%.0s' $(seq 1 80))
  run ry_ddev_name 3a8d "$long_project"
  [ "$status" -eq 0 ]
  [ "$output" = "3a8d-$long_project" ]
}

@test "an over-long --prefix is refused, not silently replaced, for a project with no .ddev/ too" {
  run ry-dispatch.sh --haul --prefix 1234567 xyz "x"
  [ "$status" -ne 0 ]
  [[ "$output" != *"too long for a DDEV project name"* ]]
  [ -z "$(ls "$RY_HOME/state")" ]
}

# --- couple ------------------------------------------------------------------

@test "couple writes the override with <prefix>-<project>" {
  make_ddev_project xyz
  id=$(ry-dispatch.sh --haul --prefix 308 xyz "x" | sed -n 's/^id=//p')
  f="$RY_HOME/yard/xyz/$id/.ddev/config.local.yaml"
  [ -f "$f" ]
  grep -q '^name: 308-xyz$' "$f"
  # and it does not dirty the siding
  [ -z "$(git -C "$RY_HOME/yard/xyz/$id" status --porcelain)" ]
}

# A meta with no prefix line was written before railyard recorded one; couple
# recomputes the default from the id alone, so it must land on the same digest.
@test "couple rebuilds the default prefix from the id when the meta has none" {
  lib
  make_ddev_project xyz
  a=$(ry-dispatch.sh --haul xyz "a" | sed -n 's/^id=//p')
  b=$(ry-dispatch.sh --haul --after "$a" --slug "news filter styling" xyz "b" | sed -n 's/^id=//p')
  sed -i.bak '/^prefix=/d' "$RY_HOME/state/$b.meta"     # meta from before --prefix
  run ry-couple.sh "$b"
  [ "$status" -eq 0 ]
  grep -q "^name: $(ry_ddev_default_prefix "$b")-xyz\$" "$RY_HOME/yard/xyz/$b/.ddev/config.local.yaml"
}

@test "a project without .ddev/ is untouched" {
  id=$(ry-dispatch.sh --haul xyz "x" | sed -n 's/^id=//p')
  [ ! -e "$RY_HOME/yard/xyz/$id/.ddev" ]
  [ -z "$(git -C "$RY_HOME/yard/xyz/$id" status --porcelain)" ]
}

@test "a project that tracks config.local.yaml fails loudly and writes nothing" {
  make_ddev_project xyz --tracked
  # the project really does track it: the failure path under test is "tracked",
  # not merely "no ignore rule"
  git -C "$RY_HOME/projects/xyz" ls-files --error-unmatch .ddev/config.local.yaml
  run ry-dispatch.sh --haul xyz "x"
  [ "$status" -ne 0 ]
  [[ "$output" == *"gitignore"* ]]
  [[ "$output" == *"xyz"* ]]
  [ -z "$(ls "$RY_HOME/yard/xyz" 2>/dev/null)" ]
}

@test "a failed override write is reported, not swallowed as success" {
  [ "$(id -u)" -ne 0 ] || skip "root ignores the read-only directory"
  lib
  make_ddev_project xyz
  siding="$BATS_TEST_TMPDIR/probe-siding"
  git -C "$RY_HOME/projects/xyz" worktree add -q -b probe "$siding" origin/main
  chmod a-w "$siding/.ddev"
  run ry_ddev_write_override "$siding" xyz 308
  chmod u+w "$siding/.ddev"
  [ "$status" -ne 0 ]
  [ ! -f "$siding/.ddev/config.local.yaml" ]
}

# --- decouple ----------------------------------------------------------------

@test "decouple deletes the siding's DDEV project before the worktree goes" {
  make_ddev_project xyz
  id=$(ry-dispatch.sh --haul --prefix 308 xyz "x" | sed -n 's/^id=//p')
  run ry-decouple.sh "$id"
  [ "$status" -eq 0 ]
  grep -q -- '308-xyz' "$RY_FAKE_DDEV_LOG"
  [ ! -e "$RY_HOME/yard/xyz/$id" ]
}

# The real `ddev delete` prompts and waits on stdin; the fake refuses a delete
# without --yes for that reason. Drop the flag and this test goes red.
@test "the delete is non-interactive: --yes is passed" {
  make_ddev_project xyz
  id=$(ry-dispatch.sh --haul --prefix 308 xyz "x" | sed -n 's/^id=//p')
  run ry-decouple.sh "$id"
  [ "$status" -eq 0 ]
  grep -qE -- '(--yes|(^| )-[A-Za-z]*y)' "$RY_FAKE_DDEV_LOG"
  # and the fake really would have caught its absence
  run "$BATS_TEST_DIRNAME/fakebin/ddev" delete --omit-snapshot 308-xyz
  [ "$status" -ne 0 ]
  [[ "$output" == *"prompt"* ]] || [[ "$output" == *"hang"* ]]
  run "$BATS_TEST_DIRNAME/fakebin/ddev" delete -Oy 308-xyz
  [ "$status" -eq 0 ]
}

# A siding cut before this change has .ddev/ and no override, and its DDEV
# project is exactly the orphan that had to be cleared by hand for #308.
@test "a siding with no override is deleted by the name rebuilt from its meta" {
  make_ddev_project xyz
  id=$(ry-dispatch.sh --haul --prefix 308 xyz "x" | sed -n 's/^id=//p')
  rm -f "$RY_HOME/yard/xyz/$id/.ddev/config.local.yaml"
  run ry-decouple.sh "$id"
  [ "$status" -eq 0 ]
  grep -q -- '308-xyz' "$RY_FAKE_DDEV_LOG"
  [ ! -e "$RY_HOME/yard/xyz/$id" ]
}

@test "with no override and no prefix in the meta, the project's own config.yaml names it" {
  make_ddev_project xyz
  id=$(ry-dispatch.sh --haul xyz "x" | sed -n 's/^id=//p')
  rm -f "$RY_HOME/yard/xyz/$id/.ddev/config.local.yaml"
  sed -i.bak '/^prefix=/d' "$RY_HOME/state/$id.meta"    # meta from before --prefix
  run ry-decouple.sh "$id"
  [ "$status" -eq 0 ]
  grep -q -- ' xyz$' "$RY_FAKE_DDEV_LOG"                # .ddev/config.yaml's name
  [ ! -e "$RY_HOME/yard/xyz/$id" ]
}

@test "all three name sources absent: decouple says so and still finishes" {
  make_ddev_project xyz
  id=$(ry-dispatch.sh --haul xyz "x" | sed -n 's/^id=//p')
  rm -f "$RY_HOME/yard/xyz/$id/.ddev/config.local.yaml" \
        "$RY_HOME/yard/xyz/$id/.ddev/config.yaml"
  sed -i.bak '/^prefix=/d' "$RY_HOME/state/$id.meta"
  run ry-decouple.sh --force "$id"     # --force: config.yaml is tracked, so its removal dirties the siding
  [ "$status" -eq 0 ]
  [[ "$output" == *"no DDEV project name"* ]]
  [ ! -e "$RY_HOME/yard/xyz/$id" ]
  [ ! -s "$RY_FAKE_DDEV_LOG" ]
}

# ry-decouple.sh runs under set -euo pipefail: a sed on a file that is not
# there used to fail the pipeline and exit before git worktree remove.
@test "a missing override does not abort the decouple under set -euo pipefail" {
  make_ddev_project xyz
  id=$(ry-dispatch.sh --haul xyz "x" | sed -n 's/^id=//p')
  rm -f "$RY_HOME/yard/xyz/$id/.ddev/config.local.yaml"
  run ry-decouple.sh "$id"
  [ "$status" -eq 0 ]
  [ ! -e "$RY_HOME/yard/xyz/$id" ]
  [ -f "$RY_HOME/state/archive/$id/meta" ]              # it reached the archive
  ! git -C "$RY_HOME/projects/xyz" worktree list | grep -q "yard/xyz/$id"
}

@test "decouple runs no ddev for a project without .ddev/" {
  id=$(ry-dispatch.sh --haul xyz "x" | sed -n 's/^id=//p')
  run ry-decouple.sh "$id"
  [ "$status" -eq 0 ]
  [ ! -s "$RY_FAKE_DDEV_LOG" ]
}

@test "a failing ddev does not block the decouple" {
  make_ddev_project xyz
  id=$(ry-dispatch.sh --haul xyz "x" | sed -n 's/^id=//p')
  RY_FAKE_DDEV_FAIL=1 run ry-decouple.sh "$id"
  [ "$status" -eq 0 ]
  [ ! -e "$RY_HOME/yard/xyz/$id" ]
  [ ! -f "$RY_HOME/state/$id.meta" ]
}

@test "a missing ddev binary does not block the decouple" {
  make_ddev_project xyz
  id=$(ry-dispatch.sh --haul xyz "x" | sed -n 's/^id=//p')
  PATH="$BATS_TEST_DIRNAME/../bin:/usr/bin:/bin" run ry-decouple.sh "$id"
  [ "$status" -eq 0 ]
  [ ! -e "$RY_HOME/yard/xyz/$id" ]
}

# --- old sidings --------------------------------------------------------------
# A siding cut before the 6-character cap has a long prefix in its meta and an
# override file naming <that prefix>-<project>. The cap lives at dispatch only:
# decouple must still resolve and delete that DDEV project, from the override
# first and from the meta when the override is gone.
@test "decouple still deletes the DDEV project of a siding with a pre-cap 21-character prefix" {
  make_ddev_project xyz
  id=$(ry-dispatch.sh --haul --slug "latest commit on main" xyz "x" | sed -n 's/^id=//p')
  old=latest-commit-on-main                              # 21 characters, as recorded before #36
  sed -i.bak "s/^prefix=.*/prefix=$old/" "$RY_HOME/state/$id.meta"
  printf 'name: %s-xyz\n' "$old" > "$RY_HOME/yard/xyz/$id/.ddev/config.local.yaml"
  run ry-decouple.sh "$id"
  [ "$status" -eq 0 ]
  grep -q -- " $old-xyz\$" "$RY_FAKE_DDEV_LOG"
  [ ! -e "$RY_HOME/yard/xyz/$id" ]
}

@test "with no override, a pre-cap long prefix in the meta still names the DDEV project to delete" {
  make_ddev_project xyz
  id=$(ry-dispatch.sh --haul --slug "latest commit on main" xyz "x" | sed -n 's/^id=//p')
  old=latest-commit-on-main
  sed -i.bak "s/^prefix=.*/prefix=$old/" "$RY_HOME/state/$id.meta"
  rm -f "$RY_HOME/yard/xyz/$id/.ddev/config.local.yaml"
  run ry-decouple.sh "$id"
  [ "$status" -eq 0 ]
  grep -q -- " $old-xyz\$" "$RY_FAKE_DDEV_LOG"
  [ ! -e "$RY_HOME/yard/xyz/$id" ]
}

# --- long project names -------------------------------------------------------
# The 63-character total check is gone by decision (#36): the project name has
# no limit, and railyard raises no length complaint about it.
@test "an 80-character project name dispatches with no length complaint" {
  long_project=$(printf 'p%.0s' $(seq 1 80))
  make_project "$long_project"
  make_ddev_project "$long_project"
  run ry-dispatch.sh --haul --ticket 3 --slug "fixtures start script" "$long_project" "x"
  [ "$status" -eq 0 ]
  [[ "$output" != *"too long"* ]]
  [[ "$output" != *"63"* ]]
  id=$(sed -n 's/^id=//p' <<<"$output")
  prefix=$(sed -n 's/^prefix=//p' "$RY_HOME/state/$id.meta")
  [ "${#prefix}" -eq 6 ]
  grep -q "^name: $prefix-$long_project\$" "$RY_HOME/yard/$long_project/$id/.ddev/config.local.yaml"
}
