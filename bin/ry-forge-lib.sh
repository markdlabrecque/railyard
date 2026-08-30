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
