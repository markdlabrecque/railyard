#!/usr/bin/env bash
# Launch the engine for a dispatched id in the configured backend.
# Writes state/<id>.settings.json (Claude hooks: Stop -> ry-engine-stop.sh),
# pre-trusts the siding in ~/.claude.json (RY_CLAUDE_JSON overrides) so no
# trust dialog blocks the engine, opens the backend window, marks running.
#
# usage: ry-engine-launch.sh <id>
# env:   RY_BACKEND=tmux|none  RY_ENGINE_CMD (default: claude --dangerously-skip-permissions)
set -euo pipefail
# shellcheck source=bin/ry-lib.sh
. "$(dirname "$0")/ry-lib.sh"
# shellcheck source=bin/ry-tmux-lib.sh
. "$(dirname "$0")/ry-tmux-lib.sh"

id=${1:-}; [ -n "$id" ] || ry_die "need <id>"
home=$(ry_home)
bindir=$(cd "$(dirname "$0")" && pwd)
siding=$(ry_meta_get "$id" siding)
[ -d "$siding" ] || ry_die "siding $siding missing"
waybill=$(cat "$home/state/$id.waybill.md")
settings="$home/state/$id.settings.json"

jq -n --arg cmd "exec $bindir/ry-engine-stop.sh" '{hooks:{Stop:[{hooks:[{type:"command",command:$cmd}]}]}}' > "$settings"

engine_cmd=${RY_ENGINE_CMD:-claude --dangerously-skip-permissions}
# Env travels through the window command so the Stop hook can find home + id.
cmd="export CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false RY_HOME=$(printf %q "$home") RY_ID=$(printf %q "$id") RY_BIN=$(printf %q "$bindir"); "
cmd+="$engine_cmd --settings $(printf %q "$settings") $(printf %q "$waybill")"

ry_claude_trust "$siding"

case ${RY_BACKEND:-tmux} in
  tmux)
    window="ry-$id"
    ry_tmux_open_window "$window" "$siding" "$cmd"
    printf 'window=%s\n' "$window" >> "$home/state/$id.meta"
    ;;
  none) ry_die "RY_BACKEND=none: nothing to launch" ;;
  *)    ry_die "unknown RY_BACKEND '$RY_BACKEND'" ;;
esac
ry_set_status "$id" running
printf 'launched %s\n' "$id"
