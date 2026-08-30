#!/usr/bin/env bash
# Send follow-up text to a running or turn-ended engine (it keeps its context)
# and mark it running again so the watcher tracks the next turn end.
# usage: ry-send.sh <id> "<text>"
set -euo pipefail
# shellcheck source=bin/ry-lib.sh
. "$(dirname "$0")/ry-lib.sh"
# shellcheck source=bin/ry-backend-lib.sh
. "$(dirname "$0")/ry-backend-lib.sh"
case ${1:-} in -h|--help) ry_usage "$0"; exit 0 ;; esac
id=${1:-}; text=${2:-}
[ -n "$id" ] && [ -n "$text" ] || ry_die "usage: ry-send.sh <id> \"<text>\""
ry_backend_send "$id" "$text"
rm -f "$(ry_home)/state/$id.stall-warned"
ry_set_status "$id" running
