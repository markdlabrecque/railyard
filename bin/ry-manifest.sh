#!/usr/bin/env bash
# The manifest: every task not yet decoupled, grouped by status, with what each
# queued task waits on, plus the inbox count. Written as a report the dispatcher
# can read as-is: markdown lists, no line over 80 characters, rows led by the
# project and its ticket (AGENTS.md § Reporting style) rather than the task id.
# Read-only. usage: ry-manifest.sh
set -euo pipefail
# shellcheck source=bin/ry-lib.sh
. "$(dirname "$0")/ry-lib.sh"
case ${1:-} in -h|--help) ry_usage "$0"; exit 0 ;; esac
home=$(ry_home); st="$home/state"
bindir=$(cd "$(dirname "$0")" && pwd)
width=80

age_of() {  # <file> -> e.g. 3m / 2h / 1d
  local s=$(( $(date +%s) - $(ry_mtime "$1") ))
  if [ "$s" -lt 3600 ]; then printf '%dm' $((s/60))
  elif [ "$s" -lt 86400 ]; then printf '%dh' $((s/3600))
  else printf '%dd' $((s/86400)); fi
}

# wrap <first-prefix> <rest-prefix> <max-lines> <text>: word-wrap text so no
# line exceeds $width. max-lines 0 means unlimited; otherwise the text is cut
# after that many lines, front kept, with "..." marking the cut. ASCII on
# purpose: BSD awk counts bytes, so a three-byte ellipsis would push a full line
# to 82. A single word wider than the line is split rather than allowed to
# overflow.
wrap() {
  printf '%s\n' "$4" | awk -v w="$width" -v first="$1" -v rest="$2" -v max="$3" '
    function flush() { print pre line; n++; pre = rest; line = "" }
    {
      pre = first; line = ""; n = 0; cut = 0
      k = split($0, words, /[[:space:]]+/)
      for (i = 1; i <= k && !cut; i++) {
        wd = words[i]; if (wd == "") continue
        cand = (line == "" ? wd : line " " wd)
        if (length(pre cand) <= w) { line = cand; continue }
        if (length(rest wd) > w) {             # a word wider than a line
          if (line != "") { line = line " " }  # fill this line before splitting
          while (length(pre line wd) > w) {
            if (max > 0 && n == max - 1) { cut = 1; line = line wd; break }
            room = w - length(pre line)
            line = line substr(wd, 1, room); wd = substr(wd, room + 1); flush()
          }
          if (!cut) line = line wd
          continue
        }
        if (max > 0 && n == max - 1) { cut = 1; break }
        flush(); line = wd
      }
      if (cut) {
        room = w - length(pre) - 3
        if (length(line) > room) line = substr(line, 1, room)
        print pre line "..."
      } else if (line != "") print pre line
    }'
}
row() { wrap "- " "  " 0 "$1"; }
sub() { wrap "  - " "    " "${2:-0}" "$1"; }

n=0 deps=""
for status in queued running turn-ended pr-open merged dispatched; do
  rows=""
  for f in "$st"/*.status; do
    [ -f "$f" ] || continue
    [ "$(cat "$f")" = "$status" ] || continue
    id=${f##*/}; id=${id%.status}
    # The project leads and the ticket follows it, per AGENTS.md § Reporting
    # style: a bare #N names a different ticket in every project. Then shape,
    # mode and age; the id closes the row because it is what bin/ scripts take.
    ticket=$(ry_meta_get "$id" ticket); project=$(ry_meta_get "$id" project)
    shape=$(ry_meta_get "$id" shape); mode=$(ry_meta_get "$id" mode)
    head_=$project; [ -n "$ticket" ] && head_+=" #$ticket"; head_+=" $shape"
    [ -n "$mode" ] && [ "$mode" != none ] && head_+=", $mode"
    line=$(row "$head_, $(age_of "$f"): $id")
    url=$(ry_meta_get "$id" pr_url)
    [ -z "$url" ] || line+=$'\n'"  - $url"   # a URL is never wrapped
    if [ "$status" = queued ]; then
      deps=$("$bindir/ry-deps.sh" "$id" 2>/dev/null || true)
      case $deps in
        state=stranded*)
          line+=$'\n'"$(sub "**stranded**: ${deps#state=stranded stranded=} was dropped without merging. Drop this task or release the block.")" ;;
        state=pending*)
          line+=$'\n'"$(sub "waiting on ${deps#state=pending pending=}")" ;;
      esac
    fi
    if [ -f "$st/$id.last.md" ]; then
      # The handoff's first line says what happened. Two lines of it is the
      # budget; the front of the sentence is the part that carries the news.
      # A handoff with no first line (an engine that ended on a tool call)
      # adds no line: a blank inside the list reads as a rendering glitch.
      summary=$(sub "$(head -n1 "$st/$id.last.md")" 2)
      [ -z "$summary" ] || line+=$'\n'"$summary"
      # Surface the risk line too, so a finished task worth a look stands out
      # without opening its handoff. Scoped to the Inspection block: a
      # `- risk:` line quoted in the handoff's prose is not a verdict.
      risk_line=$(awk '
        /^##[[:space:]]+Inspection[[:space:]]*$/ { f=1; next }
        f && (/^#/ || /^```/) { exit }
        f && /^- risk:/ { sub(/^- /, ""); print; exit }' "$st/$id.last.md")
      [ -n "$risk_line" ] && line+=$'\n'"$(sub "$risk_line")"
    fi
    rows+="$line"$'\n'; n=$((n+1))
  done
  [ -n "$rows" ] && printf '%s\n\n%s\n' "$status" "$rows"
done
[ "$n" -gt 0 ] || echo "no tasks"
unread=0; [ -s "$st/inbox.md" ] && unread=$(grep -c . "$st/inbox.md")
printf 'inbox: %d unread\n' "$unread"
