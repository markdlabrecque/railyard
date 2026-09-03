#!/usr/bin/env bash
# Print a reference the dispatcher can act on: project, #N or !N, full URL --
# one line per object, so a report never has to guess a link or a project.
# Read-only.
# usage: ry-ref.sh <id>                   the task's ticket and PR, if it has them
#        ry-ref.sh <project> #<n>|<n>     an issue of that project
#        ry-ref.sh <project> !<n>         a pull/merge request of that project
# Output: `<project> #<n> <url>` / `<project> !<n> <url>`. A task with neither a
# ticket nor a PR prints `<project> <id> (no ticket, no URL)` and exits 0: it is
# still qualified, it just has nothing to link.
set -euo pipefail
# shellcheck source=bin/ry-lib.sh
. "$(dirname "$0")/ry-lib.sh"
# shellcheck source=bin/ry-forge-lib.sh
. "$(dirname "$0")/ry-forge-lib.sh"
case ${1:-} in -h|--help) ry_usage "$0"; exit 0 ;; '') ry_usage "$0" >&2; exit 2 ;; esac
home=$(ry_home)

remote_of() {  # <project> -> origin url, or die
  # `$(...)` does not inherit set -e, so a die inside ry_project_dir would
  # only end that substitution and git would happily read the cwd's origin.
  local dir
  dir=$(ry_project_dir "$1") || exit 1
  git -C "$dir" remote get-url origin 2>/dev/null \
    || ry_die "project '$1' has no origin remote"
}

if [ $# -eq 1 ]; then
  id=$1
  [ -f "$home/state/$id.meta" ] || ry_die "unknown id '$id' (no state/$id.meta; try: ry-ref.sh <project> #<n>)"
  project=$(ry_meta_get "$id" project)
  ticket=$(ry_meta_get "$id" ticket)
  pr_url=$(ry_meta_get "$id" pr_url)
  printed=0
  if [ -n "$ticket" ]; then
    remote=$(remote_of "$project")
    url=$(ry_ticket_url "$remote" "$ticket") \
      || ry_die "cannot derive a web URL from $project's remote ($remote)"
    printf '%s #%s %s\n' "$project" "$ticket" "$url"; printed=1
  fi
  if [ -n "$pr_url" ]; then
    # Recorded verbatim by ry-pr.sh when the PR was opened: never rebuilt.
    printf '%s !%s %s\n' "$project" "$(ry_pr_number "$pr_url")" "$pr_url"; printed=1
  fi
  [ "$printed" -eq 1 ] || printf '%s %s (no ticket, no URL)\n' "$project" "$id"
  exit 0
fi

[ $# -eq 2 ] || { ry_usage "$0" >&2; exit 2; }
project=$1 ref=$2
case $ref in
  '!'*) kind='pr'; n=${ref#!} ;;
  '#'*) kind=ticket; n=${ref#\#} ;;
  *)    kind=ticket; n=$ref ;;
esac
case $n in
  ''|*[!0-9]*) ry_die "not a number: '$ref' (want #<n>, !<n> or <n>)" ;;
esac
remote=$(remote_of "$project")
case $kind in
  ticket) url=$(ry_ticket_url "$remote" "$n") || ry_die "cannot derive a web URL from $project's remote ($remote)"
          printf '%s #%s %s\n' "$project" "$n" "$url" ;;
  pr)     url=$(ry_pr_url "$remote" "$n") || ry_die "cannot derive a web URL from $project's remote ($remote)"
          printf '%s !%s %s\n' "$project" "$n" "$url" ;;
esac
