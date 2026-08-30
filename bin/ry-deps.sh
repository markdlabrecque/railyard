#!/usr/bin/env bash
# Report whether a task's blockers have cleared.
#
#   state=ready     no blockers, or every one of them merged
#   state=pending   at least one blocker still in flight
#   state=stranded  a blocker was decoupled without ever merging, so nothing
#                   behind it can ever clear on its own — a human must decide
#
# Stranded wins over pending: it is the one that needs a decision.
# usage: ry-deps.sh <id>
set -euo pipefail
# shellcheck source=bin/ry-lib.sh
. "$(dirname "$0")/ry-lib.sh"

id=${1:-}; [ -n "$id" ] || ry_die "need <id>"
home=$(ry_home)
after=$(ry_meta_get "$id" after)

pending="" stranded=""
for dep in ${after//,/ }; do
  case $(ry_status_of "$dep") in
    merged) ;;
    "") stranded+="${stranded:+,}$dep" ;;
    decoupled) stranded+="${stranded:+,}$dep" ;;
    *) if [ -f "$home/state/$dep.status" ]; then pending+="${pending:+,}$dep"
       else stranded+="${stranded:+,}$dep"; fi ;;
  esac
done

if   [ -n "$stranded" ]; then printf 'state=stranded stranded=%s\n' "$stranded"
elif [ -n "$pending"  ]; then printf 'state=pending pending=%s\n' "$pending"
else printf 'state=ready\n'; fi
