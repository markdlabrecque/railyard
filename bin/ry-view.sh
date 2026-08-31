#!/usr/bin/env bash
# Look at a tmux-hosted yard from another backend. The yardmaster and every
# engine run in tmux; herdr, Orca or cmux open one terminal that attaches to
# that same tmux server, so moving from the laptop to something with a phone in
# it moves the viewer, not the yard.
#
# Switching viewer changes no railyard state at all: no claim is rewritten, no
# task is touched, nothing is migrated. Close one viewer, open another.
#
# A viewer is not an engine. Railyard records nothing for it and never sends to
# it, and the backend hosting it sees `tmux` in that terminal rather than
# `claude`, so its own agent detection stays dark. That is correct — the
# yardmaster's status comes from the Stop hook and the inbox, not from the app
# it is being watched in.
#
# `new-session -t` puts each viewer in its own session in a group, so two
# viewers never fight over window size or which window is current, and the
# session goes away when the viewer detaches.
#
# usage: ry-view.sh [--dry-run] <herdr|orca|cmux>
#   --dry-run  print the attach command the viewer would run, and exit
set -euo pipefail
# shellcheck source=bin/ry-lib.sh
. "$(dirname "$0")/ry-lib.sh"
# shellcheck source=bin/ry-backend-lib.sh
. "$(dirname "$0")/ry-backend-lib.sh"

dry=false; viewer=
while [ $# -gt 0 ]; do
  case $1 in
    -h|--help) ry_usage "$0"; exit 0 ;;
    --dry-run) dry=true ;;
    -*) ry_die "unknown option '$1' (--dry-run)" ;;
    *) [ -z "$viewer" ] || ry_die "one backend at a time, not '$viewer' and '$1'"; viewer=$1 ;;
  esac
  shift
done

[ -n "$viewer" ] || ry_die "say which backend should open the viewer (herdr|orca|cmux)"
case $viewer in
  herdr|orca|cmux) ;;
  tmux) ry_die "tmux hosts the yard, it does not view it — bin/ry-yard.sh attaches to it" ;;
  *) ry_die "unknown backend '$viewer' (herdr|orca|cmux)" ;;
esac

home=$(ry_home); session=$(ry_tmux_session)
ry_tmux has-session -t "=$session" 2>/dev/null ||
  ry_die "no tmux yard called '$session' to look at — start one with RY_BACKEND=tmux bin/ry-yard.sh"

# One session per viewer, all in the yard's group. A name already taken means
# another viewer is looking; take the next one rather than stealing its client.
name=$session-$viewer; n=1
while ry_tmux has-session -t "=$name" 2>/dev/null; do n=$((n + 1)); name=$session-$viewer-$n; done

tmux_cmd=tmux
[ -z "${RY_TMUX_SOCKET:-}" ] || tmux_cmd="tmux -L $RY_TMUX_SOCKET"
# The kill-session runs once the viewer detaches, so viewer sessions do not pile up.
cmd="$tmux_cmd new-session -t $session -s $name; $tmux_cmd kill-session -t $name 2>/dev/null"

if $dry; then printf '%s\n' "$cmd"; exit 0; fi

case $viewer in
  herdr)
    ry_herdr_available || ry_die "herdr is not installed"
    ry_herdr_running || ry_die "no herdr server is running"
    t=$(ry_herdr_open railyard-view "$home" "$cmd")
    echo "viewing $session in herdr: $t" ;;
  cmux)
    ry_cmux_available || ry_die "the cmux CLI was not found"
    ws=$(ry_cmux_open railyard-view "$home" "$cmd")
    echo "viewing $session in cmux: $ws" ;;
  orca)
    command -v orca >/dev/null || ry_die "the orca CLI is not installed"
    ry_orca_ensure_repo "$home"
    h=$(ry_orca_open railyard-view "$home" "$cmd")
    echo "viewing $session in Orca: $h" ;;
esac
