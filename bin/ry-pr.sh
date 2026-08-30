#!/usr/bin/env bash
# Open a PR (GitHub via gh) or MR (GitLab via glab) for a pr-mode haul:
# push ry/<id> to origin, create the request against the base branch, record
# pr_url/forge in meta and set status pr-open. Title defaults to the single
# commit subject, or the waybill's first line when there are several.
# usage: ry-pr.sh [--title <t>] <id>
set -euo pipefail
# shellcheck source=bin/ry-lib.sh
. "$(dirname "$0")/ry-lib.sh"
# shellcheck source=bin/ry-forge-lib.sh
. "$(dirname "$0")/ry-forge-lib.sh"
case ${1:-} in -h|--help) ry_usage "$0"; exit 0 ;; esac

title="" id=""
while [ $# -gt 0 ]; do
  case $1 in --title) title=${2:-}; shift;; -*) ry_die "unknown flag $1";; *) id=$1;; esac; shift
done
[ -n "$id" ] || ry_die "need <id>"

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

git -C "$siding" push -q -u origin "$branch"
forge=$(ry_forge "$siding")
case $forge in
  github) url=$(cd "$siding" && gh pr create --base "$base" --head "$branch" --title "$title" --body "$body") ;;
  gitlab) url=$(cd "$siding" && glab mr create --source-branch "$branch" --target-branch "$base" --title "$title" --description "$body" --yes) ;;
  *) ry_die "unknown forge '$forge'" ;;
esac
url=$(grep -oE 'https?://[^ ]+/(pull|merge_requests)/[0-9]+' <<<"$url" | tail -n1)
[ -n "$url" ] || ry_die "could not parse PR url from $forge output"

printf 'forge=%s\npr_url=%s\n' "$forge" "$url" >> "$home/state/$id.meta"
ry_set_status "$id" pr-open
printf '%s\n' "$url"
