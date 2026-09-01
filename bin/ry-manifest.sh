#!/usr/bin/env bash
# The manifest: the departures board of every task not yet decoupled, grouped by
# status, with what each queued task waits on, plus the inbox count.
# Read-only. usage: ry-manifest.sh
set -euo pipefail
# shellcheck source=bin/ry-lib.sh
. "$(dirname "$0")/ry-lib.sh"
case ${1:-} in -h|--help) ry_usage "$0"; exit 0 ;; esac
home=$(ry_home); st="$home/state"
bindir=$(cd "$(dirname "$0")" && pwd)

age_of() {  # <file> -> e.g. 3m / 2h / 1d
  local s=$(( $(date +%s) - $(ry_mtime "$1") ))
  if [ "$s" -lt 3600 ]; then printf '%dm' $((s/60))
  elif [ "$s" -lt 86400 ]; then printf '%dh' $((s/3600))
  else printf '%dd' $((s/86400)); fi
}

n=0 deps=""
for status in queued running turn-ended pr-open merged dispatched; do
  rows=""
  for f in "$st"/*.status; do
    [ -f "$f" ] || continue
    [ "$(cat "$f")" = "$status" ] || continue
    id=${f##*/}; id=${id%.status}
    # The ticket leads when the task has one: it is the identifier the
    # dispatcher tracks work by. The id follows because it is what the
    # bin/ scripts take.
    label=$id; ticket=$(ry_meta_get "$id" ticket)
    [ -z "$ticket" ] || label="#$ticket  $id"
    line="  $label  $(ry_meta_get "$id" project)  $(ry_meta_get "$id" shape)  $(ry_meta_get "$id" mode)  $(age_of "$f")"
    url=$(ry_meta_get "$id" pr_url); [ -n "$url" ] && line+="  $url"
    if [ "$status" = queued ]; then
      deps=$("$bindir/ry-deps.sh" "$id" 2>/dev/null || true)
      case $deps in
        state=stranded*) line+=$'\n'"      STRANDED: ${deps#state=stranded stranded=} was dropped without merging — drop this task or release the block" ;;
        state=pending*)  line+=$'\n'"      waiting on ${deps#state=pending pending=}" ;;
      esac
    fi
    if [ -f "$st/$id.last.md" ]; then
      line+=$'\n'"      $(head -n1 "$st/$id.last.md")"
      # Surface the risk line too, so a finished task worth a look stands out
      # on the board without opening its handoff.
      risk_line=$(sed -n 's/^- risk:.*/&/p' "$st/$id.last.md" | head -n 1)
      [ -n "$risk_line" ] && line+=$'\n'"      $risk_line"
    fi
    rows+="$line"$'\n'; n=$((n+1))
  done
  [ -n "$rows" ] && printf '%s\n%s' "$(tr '[:lower:]' '[:upper:]' <<<"$status")" "$rows"
done
[ "$n" -gt 0 ] || echo "no tasks"
unread=0; [ -s "$st/inbox.md" ] && unread=$(grep -c . "$st/inbox.md")
printf 'inbox: %d unread\n' "$unread"
