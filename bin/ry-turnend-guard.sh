#!/usr/bin/env bash
# Yardmaster Stop hook: no turn ends blind. If state/inbox.md has unread engine
# events, block the turn (exit 2) and tell the yardmaster to handle them.
# Passes when stop_hook_active is true (avoids loops) or when running as an
# engine (RY_ID set). Never fails for any other reason.
set -u
# shellcheck source=bin/ry-lib.sh
. "$(dirname "$0")/ry-lib.sh"
[ -z "${RY_ID:-}" ] || exit 0
input=$(cat || true)
[ "$(jq -r '.stop_hook_active // false' <<<"$input" 2>/dev/null || echo false)" = true ] && exit 0
inbox="$(ry_home)/state/inbox.md"
[ -s "$inbox" ] || exit 0
n=$(grep -c . "$inbox")
{
  printf 'railyard: %s unread engine event(s). Handle them, then run bin/ry-inbox.sh --ack:\n' "$n"
  cat "$inbox"
} >&2
exit 2
