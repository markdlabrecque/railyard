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

# The heading is matched loosely and the block ends at the next heading of any
# depth or at a fence: an engine that copies the preamble's fenced template
# literally would otherwise leak the closing ``` into the block, and a stray
# trailing space would read as "no block at all" — a correct engine bounced for
# whitespace.
block=""
in_block=0
while IFS= read -r line || [ -n "$line" ]; do
  line=${line%$'\r'}
  if [ "$in_block" -eq 1 ]; then
    case $line in '#'*|'```'*) break ;; esac
  elif [[ $line =~ ^##[[:space:]]+Inspection[[:space:]]*$ ]]; then
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
      # The grade is a whole word: "lowkey unsure" is not a risk grade.
      case ${val%%[![:alnum:]]*} in low|medium|high) ;; *) bad+=("$key") ;; esac
      ;;
    suite)
      # The counts the preamble's format asks for, not merely a digit
      # somewhere: "reviewed issue #13" is not a suite result.
      [[ $val =~ [0-9]+[[:space:]]+passed ]] &&
      [[ $val =~ [0-9]+[[:space:]]+failed ]] || bad+=("$key")
      ;;
    must-fix)
      [[ $val =~ [0-9]+[[:space:]]+raised ]] || bad+=("$key")
      ;;
    "revert check")
      # Either a real file:line, or the documented escape hatch with a reason.
      if ! [[ $val =~ [^[:space:]]:[0-9]+ ]] &&
         ! [[ $val =~ ^not\ applicable[[:punct:][:space:]]+[^[:space:]] ]]; then
        bad+=("$key")
      fi
      ;;
  esac
done

if [ ${#bad[@]} -gt 0 ]; then
  RY_EXIT=3 ry_die "malformed inspection block, offending field(s): ${bad[*]}"
fi

printf '%s' "$block"
