#!/usr/bin/env bats
# Task ids are the name of the work: <ticket>-<slug>, or the slug alone.
load helpers

setup() { setup_home; make_project xyz; }
teardown() { teardown_tmux; }

lib() { . "$BATS_TEST_DIRNAME/../bin/ry-lib.sh"; }

dispatch_id() { ry-dispatch.sh "$@" | sed -n 's/^id=//p'; }

# --- the slug ----------------------------------------------------------------

@test "ry_slugify lowercases, hyphenates and keeps the first few words" {
  lib
  [ "$(ry_slugify "Fixtures start script")" = fixtures-start-script ]
  [ "$(ry_slugify "  Carry OPEN decisions!  ")" = carry-open-decisions ]
  [ "$(ry_slugify "already-a-slug")" = already-a-slug ]
  [ "$(ry_slugify "one two three four five six seven")" = one-two-three-four-five ]
  [ "$(ry_slugify $'first line\nsecond line')" = first-line ]
}

@test "ry_slugify drops ticket references, so the number is not repeated" {
  lib
  [ "$(ry_slugify "Implement issue #16 properly")" = implement-issue-properly ]
}

@test "ry_slugify always yields something usable as a path component" {
  lib
  [ "$(ry_slugify "")" = task ]
  [ "$(ry_slugify "!!! ???")" = task ]
  local s
  s=$(ry_slugify "a very long description that keeps going and going and going")
  [ "${#s}" -le 40 ]
  [[ "$s" =~ ^[a-z0-9][a-z0-9-]*$ ]]
}

@test "ry_ticket_ref takes the first ticket reference in the first line, or nothing" {
  lib
  [ "$(ry_ticket_ref "fix #16 and #17")" = 16 ]
  [ "$(ry_ticket_ref "no ticket here")" = "" ]
  [ "$(ry_ticket_ref $'plain first line\nfix #16')" = "" ]
}

# --- the id ------------------------------------------------------------------

@test "a dispatch against a ticket is named <number>-<slug>" {
  id=$(dispatch_id --haul --ticket 3 --slug "fixtures start script" xyz "wb")
  [ "$id" = 3-fixtures-start-script ]
  grep -q '^ticket=3$' "$RY_HOME/state/$id.meta"
  [ -d "$RY_HOME/yard/xyz/3-fixtures-start-script" ]
  [ "$(git -C "$RY_HOME/yard/xyz/$id" rev-parse --abbrev-ref HEAD)" = "ry/$id" ]
}

@test "a leading hash on --ticket is accepted, and a non-number is refused" {
  id=$(dispatch_id --haul --ticket '#7' --slug "carry open decisions" xyz "wb")
  [ "$id" = 7-carry-open-decisions ]
  run ry-dispatch.sh --haul --ticket abc xyz "wb"
  [ "$status" -ne 0 ]
  [[ "$output" == *"--ticket"* ]]
}

@test "a dispatch with no ticket is named by the slug alone: no number, no date" {
  id=$(dispatch_id --haul --slug "news filter styling" xyz "wb")
  [ "$id" = news-filter-styling ]
  grep -q '^ticket=$' "$RY_HOME/state/$id.meta"
}

@test "ticket and slug are read off the waybill when neither flag is given" {
  id=$(dispatch_id --haul xyz "Fix #16 news filter styling")
  [ "$id" = 16-fix-news-filter-styling ]
}

@test "every state file and the siding use the id" {
  id=$(dispatch_id --haul --ticket 3 --slug "fixtures start script" xyz "wb")
  for f in meta status waybill.md; do [ -f "$RY_HOME/state/$id.$f" ]; done
  grep -q "^siding=$RY_HOME/yard/xyz/$id\$" "$RY_HOME/state/$id.meta"
  grep -q "^branch=ry/$id\$" "$RY_HOME/state/$id.meta"
  [ -d "$RY_HOME/yard/xyz/$id" ]
}

# --- collisions --------------------------------------------------------------

# Two tasks on one ticket is routine: a first attempt and a retry, or one
# ticket split in two. Drop the counter in ry_new_id and this test goes red on
# the second id -- and the second dispatch would then overwrite the first
# task's meta, waybill and status, and fail to cut its worktree.
@test "two tasks on the same ticket do not collide: the second is -2" {
  a=$(dispatch_id --haul --ticket 3 --slug "fixtures start script" xyz "first attempt")
  b=$(dispatch_id --haul --ticket 3 --slug "fixtures start script" xyz "retry")
  c=$(dispatch_id --haul --ticket 3 --slug "fixtures start script" xyz "third")
  [ "$a" = 3-fixtures-start-script ]
  [ "$b" = 3-fixtures-start-script-2 ]
  [ "$c" = 3-fixtures-start-script-3 ]
  [ "$(cat "$RY_HOME/state/$a.waybill.md")" = "first attempt" ]
  [ "$(cat "$RY_HOME/state/$b.waybill.md")" = "retry" ]
  [ -d "$RY_HOME/yard/xyz/$a" ] && [ -d "$RY_HOME/yard/xyz/$b" ]
  [ "$(git -C "$RY_HOME/yard/xyz/$b" rev-parse --abbrev-ref HEAD)" = "ry/$b" ]
}

@test "a decoupled task still holds its name: its retry does not reuse the id" {
  a=$(dispatch_id --haul --ticket 3 --slug "fixtures start script" xyz "first")
  ry-decouple.sh --force "$a" >/dev/null
  [ -f "$RY_HOME/state/archive/$a/meta" ]
  b=$(dispatch_id --haul --ticket 3 --slug "fixtures start script" xyz "retry")
  [ "$b" = 3-fixtures-start-script-2 ]
  # the archived task's record survives untouched
  grep -q '^first$' "$RY_HOME/state/archive/$a/waybill.md"
}

@test "two projects can each have a task of the same name" {
  make_project abc
  a=$(dispatch_id --haul --slug "news filter styling" xyz "wb")
  b=$(dispatch_id --haul --slug "news filter styling" abc "wb")
  [ "$a" != "$b" ]
  [ -d "$RY_HOME/yard/xyz/$a" ] && [ -d "$RY_HOME/yard/abc/$b" ]
}

# --- old ids -----------------------------------------------------------------

# Ids created before slugs stay valid: this is not a migration. The old shape
# goes in as a slug, so the whole lifecycle runs against a genuine old-form id.
@test "an old-form id still peeks, sends, reviews, merges and decouples" {
  setup_tmux
  id=$(dispatch_id --haul --slug "xyz-0830-1412-3f9a" xyz "wb")
  [ "$id" = xyz-0830-1412-3f9a ]
  # meta written before ticket= existed
  sed -i.bak '/^ticket=/d' "$RY_HOME/state/$id.meta"; rm -f "$RY_HOME/state/$id.meta.bak"
  siding="$RY_HOME/yard/xyz/$id"
  run ry-manifest.sh;    [ "$status" -eq 0 ]; [[ "$output" == *"$id"* ]]
  run ry-peek.sh "$id";  [ "$status" -eq 0 ]
  run ry-send.sh "$id" "carry on"; [ "$status" -eq 0 ]
  git -C "$siding" config user.email e@e; git -C "$siding" config user.name e
  git -C "$RY_HOME/projects/xyz" config user.email e@e
  git -C "$RY_HOME/projects/xyz" config user.name e
  echo feature > "$siding/feature.txt"
  git -C "$siding" add -A; git -C "$siding" commit -qm "add feature"
  run ry-review-diff.sh "$id"; [ "$status" -eq 0 ]; [[ "$output" == *"id: $id"* ]]
  run ry-merge-local.sh "$id"; [ "$status" -eq 0 ]
  [ -f "$RY_HOME/projects/xyz/feature.txt" ]
  run ry-decouple.sh "$id"; [ "$status" -eq 0 ]
  [ ! -e "$siding" ]
  [ -f "$RY_HOME/state/archive/$id/meta" ]
}

# --- the manifest ------------------------------------------------------------

@test "the manifest leads with the ticket when the task has one" {
  t=$(dispatch_id --haul --ticket 16 --slug "name work" xyz "wb")
  n=$(dispatch_id --haul --slug "news filter styling" xyz "wb")
  run ry-manifest.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"- #16 xyz haul, local-only, "* ]]
  [[ "$output" == *": $t"* ]]
  [[ "$output" == *"- xyz haul, local-only, "* ]]
  [[ "$output" != *"# $n"* ]]
}

# --- the naming rule ---------------------------------------------------------

# A convention that lives only in a ticket is a hope. These two files are where
# it binds: the yardmaster reads AGENTS.md, and every engine is handed the
# preamble.
@test "the #ticket / !change rule is stated where it binds" {
  for f in "$BATS_TEST_DIRNAME/../AGENTS.md" \
           "$BATS_TEST_DIRNAME/../templates/engine-preamble.md"; do
    grep -q '`#N`' "$f" || { echo "$f does not define #N"; false; }
    grep -q '`!N`' "$f" || { echo "$f does not define !N"; false; }
    grep -qi 'commit hash' "$f" || { echo "$f does not ban leading with a hash"; false; }
    grep -qi 'carve-out' "$f" || { echo "$f is missing the GitHub carve-out"; false; }
  done
}
