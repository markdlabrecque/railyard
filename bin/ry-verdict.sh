#!/usr/bin/env bash
# Print an engine's Inspection block from its handoff, and reject a handoff
# whose Inspection block is missing or malformed -- that is what makes the
# handoff format load-bearing rather than hoped-for.
# usage: ry-verdict.sh <id>
set -euo pipefail
# shellcheck source=bin/ry-lib.sh
. "$(dirname "$0")/ry-lib.sh"
case ${1:-} in -h|--help) ry_usage "$0"; exit 0 ;; esac

id=${1:-}
[ -n "$id" ] || ry_die "need <id>"

shape=$(ry_meta_get "$id" shape)
last="$(ry_home)/state/$id.last.md"

if [ "$shape" = survey ]; then
  echo "shape is survey: no inspection block is expected"
  exit 0
fi

[ -f "$last" ] || { RY_EXIT=2 ry_die "no handoff at $last"; }

block=""
in_block=0
while IFS= read -r line || [ -n "$line" ]; do
  if [ "$in_block" -eq 1 ] && [[ $line == "## "* ]]; then
    break
  fi
  if [ "$in_block" -eq 0 ] && [ "$line" = "## Inspection" ]; then
    in_block=1
  fi
  if [ "$in_block" -eq 1 ]; then
    block+="$line"$'\n'
  fi
done < "$last"

[ -n "$block" ] || { RY_EXIT=2 ry_die "no ## Inspection block in $last"; }

get_field() {  # <key> -> its value, from $block
  printf '%s' "$block" | sed -n "s/^- $1: *//p" | head -n 1
}

not_run_re='^not run \([^)]+\)$'
bad=()
for key in inspector suite must-fix "revert check" risk; do
  val=$(get_field "$key")
  if [ -z "${val// }" ]; then
    bad+=("$key")
    continue
  fi
  case $key in
    inspector)
      if [ "$val" != ran ] && ! [[ $val =~ $not_run_re ]]; then
        bad+=("$key")
      fi
      ;;
    risk)
      case $val in low*|medium*|high*) ;; *) bad+=("$key") ;; esac
      ;;
  esac
done

if [ ${#bad[@]} -gt 0 ]; then
  RY_EXIT=3 ry_die "malformed inspection block, offending field(s): ${bad[*]}"
fi

printf '%s' "$block"
