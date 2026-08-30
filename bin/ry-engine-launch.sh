#!/usr/bin/env bash
# Launch the engine for a dispatched id in the configured backend.
# Builds the prompt from templates/engine-preamble.md + the waybill, writes
# state/<id>.settings.json (Claude hooks: Stop -> ry-engine-stop.sh),
# pre-trusts the siding in ~/.claude.json (RY_CLAUDE_JSON overrides) so no
# trust dialog blocks the engine, opens the backend window, marks running.
#
# usage: ry-engine-launch.sh <id>
# env:   RY_BACKEND=tmux|orca|none  RY_ENGINE_CMD (default: claude --dangerously-skip-permissions)
set -euo pipefail
# shellcheck source=bin/ry-lib.sh
. "$(dirname "$0")/ry-lib.sh"
# shellcheck source=bin/ry-backend-lib.sh
. "$(dirname "$0")/ry-backend-lib.sh"
case ${1:-} in -h|--help) ry_usage "$0"; exit 0 ;; esac

id=${1:-}; [ -n "$id" ] || ry_die "need <id>"
home=$(ry_home)
bindir=$(cd "$(dirname "$0")" && pwd)
siding=$(ry_meta_get "$id" siding)
[ -d "$siding" ] || ry_die "siding $siding missing"
shape=$(ry_meta_get "$id" shape); branch=$(ry_meta_get "$id" branch)
report="$home/data/$id/report.md"; mkdir -p "$home/data/$id"
# Prompt = templates/engine-preamble.md with placeholders filled, waybill last.
prompt=$(awk -v id="$id" -v shape="$shape" -v branch="$branch" -v report="$report" -v wb="$home/state/$id.waybill.md" '
  /\{\{waybill\}\}/ { while ((getline l < wb) > 0) print l; next }
  { gsub(/\{\{id\}\}/, id); gsub(/\{\{shape\}\}/, shape); gsub(/\{\{branch\}\}/, branch); gsub(/\{\{report\}\}/, report); print }
' "$bindir/../templates/engine-preamble.md")
settings="$home/state/$id.settings.json"

jq -n --arg cmd "exec $bindir/ry-engine-stop.sh" '{hooks:{Stop:[{hooks:[{type:"command",command:$cmd}]}]}}' > "$settings"

engine_cmd=${RY_ENGINE_CMD:-claude --dangerously-skip-permissions}
# Env travels through the window command so the Stop hook can find home + id.
cmd="export CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false RY_BACKEND=$(printf %q "$(ry_backend)") RY_HOME=$(printf %q "$home") RY_ID=$(printf %q "$id") RY_BIN=$(printf %q "$bindir"); "
cmd+="$engine_cmd --settings $(printf %q "$settings") $(printf %q "$prompt")"

ry_claude_trust "$siding"

ry_backend_check
target=$(ry_backend_open "$id" "$siding" "$cmd")
printf 'backend=%s\ntarget=%s\n' "$(ry_backend)" "$target" >> "$home/state/$id.meta"
ry_set_status "$id" running
printf 'launched %s\n' "$id"
