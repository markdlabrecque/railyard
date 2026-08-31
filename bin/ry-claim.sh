#!/usr/bin/env bash
# Look at, drop, or take the yard claim — state/yardmaster.claim, the terminal
# the watcher nudges to wake the yardmaster.
#
# A dead claim needs none of this: a session whose terminal has gone takes the
# yard on its own at session start. This is for the case the automatic check
# cannot see — the terminal is still open but the agent in it is gone, so the
# claim looks alive and every new session stands down. Dropping or taking a
# claim whose terminal is still live needs --force, because the cost of being
# wrong is two yardmasters drawing from one inbox.
#
# usage: ry-claim.sh [--show] | --release [--force] | --take [--force]
#   --show     who holds the yard, and whether that terminal is still there (default)
#   --release  drop the claim, so the next session to start takes the yard
#   --take     claim the yard for this session's terminal
#   --force    act even though the holding terminal is still alive
set -euo pipefail
# shellcheck source=bin/ry-lib.sh
. "$(dirname "$0")/ry-lib.sh"
# shellcheck source=bin/ry-backend-lib.sh
. "$(dirname "$0")/ry-backend-lib.sh"

action=show; force=false
while [ $# -gt 0 ]; do
  case $1 in
    -h|--help) ry_usage "$0"; exit 0 ;;
    --show|--release|--take) action=${1#--} ;;
    --force) force=true ;;
    *) ry_die "unknown option '$1' (--show|--release|--take|--force)" ;;
  esac
  shift
done

claim=$(ry_backend_claim_file)
held_backend=$(ry_claim_get backend); held=$(ry_claim_get target)
alive=false
if [ -n "$held" ] && ry_claim_alive "$held_backend" "$held"; then alive=true; fi

case $action in
  show)
    if [ -z "$held" ]; then
      echo "the yard is unclaimed"
    else
      if $alive; then state=alive; else state=gone; fi
      printf 'the yard is held on %s by %s (terminal %s)\n' "$held_backend" "$held" "$state"
      if [ "$held" = "$(ry_backend_self)" ] && [ "$held_backend" = "$(ry_backend)" ]; then
        echo "that terminal is this one"
      fi
    fi ;;

  release)
    [ -n "$held" ] || { echo "the yard is already unclaimed"; exit 0; }
    if $alive && ! $force; then
      ry_die "$held on $held_backend still holds the yard and its terminal is alive. Releasing it lets a second yardmaster start beside it, and they share one inbox. If that terminal's agent is gone, say so with --force."
    fi
    rm -f "$claim"
    printf 'released the yard, held on %s by %s\n' "$held_backend" "$held" ;;

  take)
    self=$(ry_backend_self)
    [ -n "$self" ] || ry_die "this session has no $(ry_backend) terminal to hold the yard with"
    if [ -n "$held" ] && [ "$held" != "$self" ] && $alive && ! $force; then
      ry_die "$held on $held_backend still holds the yard and its terminal is alive. Taking it from a live yardmaster leaves two of us on one inbox. If that terminal's agent is gone, say so with --force."
    fi
    ry_claim_write "$(ry_backend)" "$self"
    printf 'took the yard on %s as %s\n' "$(ry_backend)" "$self" ;;
esac
