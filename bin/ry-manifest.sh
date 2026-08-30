#!/usr/bin/env bash
# The manifest: the departures board of every engine grouped by status, plus the inbox count.
# Read-only. usage: ry-manifest.sh
set -euo pipefail
# shellcheck source=bin/ry-lib.sh
. "$(dirname "$0")/ry-lib.sh"
home=$(ry_home); st="$home/state"

age_of() {  # <file> -> e.g. 3m / 2h / 1d
  local s=$(( $(date +%s) - $(stat -f %m "$1" 2>/dev/null || stat -c %Y "$1") ))
  if [ "$s" -lt 3600 ]; then printf '%dm' $((s/60))
  elif [ "$s" -lt 86400 ]; then printf '%dh' $((s/3600))
  else printf '%dd' $((s/86400)); fi
}

n=0
for status in running turn-ended pr-open merged dispatched blocked; do
  rows=""
  for f in "$st"/*.status; do
    [ -f "$f" ] || continue
    [ "$(cat "$f")" = "$status" ] || continue
    id=${f##*/}; id=${id%.status}
    line="  $id  $(ry_meta_get "$id" project)  $(ry_meta_get "$id" shape)  $(ry_meta_get "$id" mode)  $(age_of "$f")"
    url=$(ry_meta_get "$id" pr_url); [ -n "$url" ] && line+="  $url"
    [ -f "$st/$id.last.md" ] && line+=$'\n'"      $(head -n1 "$st/$id.last.md")"
    rows+="$line"$'\n'; n=$((n+1))
  done
  [ -n "$rows" ] && printf '%s\n%s' "$(tr '[:lower:]' '[:upper:]' <<<"$status")" "$rows"
done
[ "$n" -gt 0 ] || echo "no engines"
unread=0; [ -s "$st/inbox.md" ] && unread=$(grep -c . "$st/inbox.md")
printf 'inbox: %d unread\n' "$unread"
