#!/usr/bin/env bash
# Open a PR (GitHub via gh) or MR (GitLab via glab) for a pr-mode haul:
# push ry/<id> to origin, create the request against the base branch, record
# pr_url/forge in meta and set status pr-open. Title defaults to the single
# commit subject, or the waybill's first line when there are several.
# Auto-merge is opt-in with --auto-merge (default method: merge). Checks
# usually do not exist for seconds-to-minutes after the push, so ry-pr.sh
# never arms or attempts a merge itself -- it only records auto_merge=<method>
# in the meta, and bin/ry-auto-merge.sh, run from the watcher, does the rest.
# usage: ry-pr.sh [--title <t>] [--auto-merge] [--auto-merge-method <merge|squash|rebase>] <id>
set -euo pipefail
# shellcheck source=bin/ry-lib.sh
. "$(dirname "$0")/ry-lib.sh"
# shellcheck source=bin/ry-forge-lib.sh
. "$(dirname "$0")/ry-forge-lib.sh"
case ${1:-} in -h|--help) ry_usage "$0"; exit 0 ;; esac

title="" id="" auto_merge=0 auto_merge_method="merge" auto_merge_method_given=0
while [ $# -gt 0 ]; do
  case $1 in
    --title) title=${2:-}; shift;;
    --auto-merge) auto_merge=1;;
    --auto-merge-method) auto_merge_method=${2:-}; auto_merge_method_given=1; shift;;
    -*) ry_die "unknown flag $1";;
    *) id=$1;;
  esac; shift
done
[ -n "$id" ] || ry_die "need <id>"
[ "$auto_merge" -eq 1 ] || [ "$auto_merge_method_given" -eq 0 ] \
  || ry_die "--auto-merge-method needs --auto-merge"
case $auto_merge_method in merge|squash|rebase) ;; *) ry_die "unknown --auto-merge-method '$auto_merge_method'";; esac

home=$(ry_home)
mode=$(ry_meta_get "$id" mode);   base=$(ry_meta_get "$id" base)
branch=$(ry_meta_get "$id" branch); siding=$(ry_meta_get "$id" siding)
[ "$mode" = pr ] || ry_die "mode is '$mode', not pr"
[ -z "$(ry_meta_get "$id" pr_url)" ] || ry_die "PR already open: $(ry_meta_get "$id" pr_url)"
[ -d "$siding" ] || ry_die "siding $siding missing"
[ -z "$(git -C "$siding" status --porcelain)" ] || ry_die "siding has uncommitted changes; have the engine commit first"
git -C "$siding" fetch -q origin "$base"
n=$(git -C "$siding" rev-list --count "origin/$base..HEAD" --)
[ "$n" -gt 0 ] || ry_die "no commits on $branch beyond origin/$base"

if [ -z "$title" ]; then
  if [ "$n" -eq 1 ]; then title=$(git -C "$siding" log -1 --format=%s)
  else title=$(head -n1 "$home/state/$id.waybill.md"); fi
fi
body=$(printf '%s\n\nCommits:\n%s\n' "$(cat "$home/state/$id.waybill.md")" "$(git -C "$siding" log --format='- %s' "origin/$base..HEAD" --)")

# The forge is detected, and its CLI checked, before the push: a missing gh or
# glab must not leave a pushed branch behind with no PR to go with it. Checked
# per forge, so a GitHub-only machine is never told to install glab.
forge=$(ry_forge "$siding")
case $forge in
  github) ry_require gh ;;
  gitlab) ry_require glab ;;
  *) ry_die "unknown forge '$forge'" ;;
esac

git -C "$siding" push -q -u origin "$branch"
case $forge in
  github) url=$(cd "$siding" && gh pr create --base "$base" --head "$branch" --title "$title" --body "$body") ;;
  gitlab) url=$(cd "$siding" && glab mr create --source-branch "$branch" --target-branch "$base" --title "$title" --description "$body" --yes) ;;
  *) ry_die "unknown forge '$forge'" ;;
esac
url=$(grep -oE 'https?://[^ ]+/(pull|merge_requests)/[0-9]+' <<<"$url" | tail -n1)
[ -n "$url" ] || ry_die "could not parse PR url from $forge output"

printf 'forge=%s\npr_url=%s\n' "$forge" "$url" >> "$home/state/$id.meta"
if [ "$auto_merge" -eq 1 ]; then
  printf 'auto_merge=%s\n' "$auto_merge_method" >> "$home/state/$id.meta"
fi
ry_set_status "$id" pr-open
printf '%s\n' "$url"
