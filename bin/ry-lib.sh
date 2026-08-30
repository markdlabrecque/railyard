#!/usr/bin/env bash
# Shared railyard primitives: home resolution, state files, project lookup.
# Source from other ry-*.sh scripts. Never executed directly.

ry_home() {
  if [ -n "${RY_HOME:-}" ]; then printf '%s\n' "$RY_HOME"; return; fi
  # Default: the repo that contains bin/.
  cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}

ry_die() { printf 'error: %s\n' "$*" >&2; exit "${RY_EXIT:-1}"; }

ry_new_id() {  # <project> -> e.g. xyz-0830-1412-3f9a
  local p=$1 rand
  rand=$(od -An -N2 -tx1 /dev/urandom | tr -d ' \n')
  printf '%s-%s-%s\n' "$p" "$(date +%m%d-%H%M)" "$rand"
}

ry_project_dir() {  # <name> -> projects/<name>, must be a git repo
  local home d; home=$(ry_home); d="$home/projects/$1"
  [ -d "$d/.git" ] || ry_die "unknown project '$1' (expected $d to be a git clone)"
  printf '%s\n' "$d"
}

ry_default_branch() {  # <project_dir> -> main/master/...
  local d=$1 ref
  ref=$(git -C "$d" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)
  if [ -z "$ref" ]; then
    git -C "$d" remote set-head origin -a >/dev/null 2>&1 || true
    ref=$(git -C "$d" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)
  fi
  [ -n "$ref" ] || ry_die "cannot determine default branch for $d"
  printf '%s\n' "${ref#origin/}"
}

ry_meta_get() {  # <id> <key>
  local home; home=$(ry_home)
  [ -f "$home/state/$1.meta" ] || ry_die "unknown id '$1'"
  sed -n "s/^$2=//p" "$home/state/$1.meta"
}

ry_set_status() {  # <id> <status>
  local home; home=$(ry_home)
  printf '%s\n' "$2" > "$home/state/$1.status"
}

ry_claude_trust() {  # <dir>: pre-accept Claude Code's folder-trust dialog for dir
  local f=${RY_CLAUDE_JSON:-$HOME/.claude.json} tmp
  [ -f "$f" ] || printf '{}\n' > "$f"
  tmp=$(mktemp "$f.XXXXXX")
  if jq --arg p "$1" '.projects[$p] = ((.projects[$p] // {}) + {hasTrustDialogAccepted: true})' "$f" > "$tmp"; then
    mv "$tmp" "$f"
  else
    rm -f "$tmp"; ry_die "could not update $f"
  fi
}
