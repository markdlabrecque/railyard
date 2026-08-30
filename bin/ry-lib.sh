#!/usr/bin/env bash
# Shared railyard primitives: home resolution, state files, project lookup.
# Source from other ry-*.sh scripts. Never executed directly.

ry_home() {
  if [ -n "${RY_HOME:-}" ]; then printf '%s\n' "$RY_HOME"; return; fi
  # Default: the repo that contains bin/.
  cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}

ry_usage() {  # <script>: print its header comment block, minus the shebang
  awk 'NR>1 && /^#/ { sub(/^# ?/, ""); print; next } NR>1 { exit }' "$1"
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

ry_project_base() {  # <project> -> branch sidings are cut from and merged back into
  # Order: `base:` on the project's data/projects.md line, then develop when the
  # project has one, then the remote's default branch.
  local name=$1 home pdir line b
  home=$(ry_home); pdir="$home/projects/$name"
  line=$(grep -m1 -E "^- .$name. " "$home/data/projects.md" 2>/dev/null || true)
  b=$(sed -n 's/.*base: *\([A-Za-z0-9._/-][A-Za-z0-9._/-]*\).*/\1/p' <<<"$line")
  if [ -n "$b" ]; then printf '%s\n' "$b"; return; fi
  if git -C "$pdir" rev-parse --verify -q refs/remotes/origin/develop >/dev/null 2>&1; then
    printf 'develop\n'; return
  fi
  ry_default_branch "$pdir"
}

ry_meta_get() {  # <id> <key>
  local home; home=$(ry_home)
  [ -f "$home/state/$1.meta" ] || ry_die "unknown id '$1'"
  sed -n "s/^$2=//p" "$home/state/$1.meta"
}

ry_status_of() {  # <id> -> its status, resolving through state/archive/
  # A decoupled task keeps the outcome it was archived with, so a blocker that
  # merged before being decoupled still reads as merged.
  local home id=$1 arch; home=$(ry_home)
  if [ -f "$home/state/$id.status" ]; then cat "$home/state/$id.status"; return; fi
  arch="$home/state/archive/$id"
  if [ -f "$arch/meta" ] && grep -q '^outcome=' "$arch/meta"; then
    sed -n 's/^outcome=//p' "$arch/meta"; return
  fi
  [ -f "$arch/status" ] && cat "$arch/status"
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
