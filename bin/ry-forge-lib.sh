#!/usr/bin/env bash
# Forge detection. github.com -> "github" (gh); every other host -> "gitlab"
# (glab, which reads the host from the remote, so self-hosted instances work).
# RY_FORGE overrides detection.

ry_forge_from_url() {  # <remote-url> -> github|gitlab
  case $1 in
    *github.com[:/]*) printf 'github\n' ;;
    *)                printf 'gitlab\n' ;;
  esac
}

ry_forge() {  # <repo-dir> -> github|gitlab
  if [ -n "${RY_FORGE:-}" ]; then printf '%s\n' "$RY_FORGE"; return; fi
  ry_forge_from_url "$(git -C "$1" remote get-url origin)"
}

ry_pr_number() {  # <url> -> trailing number
  printf '%s\n' "${1##*/}"
}

# --- web URLs from a remote ------------------------------------------------
# The yard's remotes come in every shape git accepts: ssh:// with a
# non-standard port and a subgroup, scp-style git@host:owner/repo, https with
# or without .git. The browser wants exactly one of them. Parameter expansion
# only -- no sed, no regex: the daily-log hook in this house lost two days of
# history to a BSD/GNU sed divergence on exactly this kind of URL.

ry_web_base() {  # <remote-url> -> https://host/group/sub/repo
  local u=$1 scheme host path
  u=${u%/}; u=${u%.git}
  case $u in
    http://*|https://*)
      # Already a web URL: keep the scheme and any port, drop only user@.
      scheme=${u%%://*}; u=${u#*://}; u=${u##*@}
      host=${u%%/*}; path=${u#*/} ;;
    *://*)
      # ssh://, git://: user@ and the ssh port are transport, not address.
      scheme=https; u=${u#*://}; u=${u##*@}
      host=${u%%/*}; host=${host%%:*}; path=${u#*/} ;;
    *@*:*|*:*)
      # scp-style git@host:owner/repo -- the colon is a separator, not a port.
      scheme=https; u=${u##*@}
      host=${u%%:*}; path=${u#*:}; path=${path#/} ;;
    *) return 1 ;;
  esac
  [ -n "$host" ] && [ -n "$path" ] && [ "$path" != "$u" ] || return 1
  printf '%s://%s/%s\n' "$scheme" "$host" "$path"
}

ry_ticket_url() {  # <remote-url> <n> -> the issue's web URL
  local base; base=$(ry_web_base "$1") || return 1
  case $(ry_forge_from_url "$1") in
    github) printf '%s/issues/%s\n' "$base" "$2" ;;
    gitlab) printf '%s/-/issues/%s\n' "$base" "$2" ;;
  esac
}

ry_pr_url() {  # <remote-url> <n> -> the pull/merge request's web URL
  local base; base=$(ry_web_base "$1") || return 1
  case $(ry_forge_from_url "$1") in
    github) printf '%s/pull/%s\n' "$base" "$2" ;;
    gitlab) printf '%s/-/merge_requests/%s\n' "$base" "$2" ;;
  esac
}
