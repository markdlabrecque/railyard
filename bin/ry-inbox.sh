#!/usr/bin/env bash
# Print the yardmaster's unread engine events. --ack moves them to
# state/inbox.archive.log so the turn-end guard lets the turn end.
# usage: ry-inbox.sh [--ack]
set -euo pipefail
# shellcheck source=bin/ry-lib.sh
. "$(dirname "$0")/ry-lib.sh"
case ${1:-} in -h|--help) ry_usage "$0"; exit 0 ;; esac
home=$(ry_home); inbox="$home/state/inbox.md"
[ -s "$inbox" ] || exit 0
cat "$inbox"
if [ "${1:-}" = --ack ]; then
  cat "$inbox" >> "$home/state/inbox.archive.log"
  : > "$inbox"
fi
