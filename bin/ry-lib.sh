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

ry_env_exports() {  # -> "K=v ..." the railyard vars a child session must inherit
  # A second yard is just a second clone, but its yardmaster only stays in its
  # own tmux session if the session (and socket) travel with it.
  local out v
  out="RY_HOME=$(printf %q "$(ry_home)")"
  for v in RY_TMUX_SESSION RY_TMUX_SOCKET; do
    if [ -n "${!v:-}" ]; then out+=" $v=$(printf %q "${!v}")"; fi
  done
  printf '%s\n' "$out"
}

ry_die() { printf 'error: %s\n' "$*" >&2; exit "${RY_EXIT:-1}"; }

ry_mtime() {  # <file> -> its mtime as a unix timestamp
  # GNU first, and the order matters. On GNU, `-f` means --file-system, where
  # `%m` is not a valid directive: it prints a placeholder and exits 0, so a
  # BSD-first fallback never fires and the caller does arithmetic on junk. BSD
  # has no `-c` at all and exits non-zero, so this order fails over on both.
  stat -c %Y "$1" 2>/dev/null || stat -f %m "$1"
}

ry_require() {  # <cmd>...: die naming everything missing, not just the first
  local c missing=()
  for c in "$@"; do command -v "$c" >/dev/null 2>&1 || missing+=("$c"); done
  [ ${#missing[@]} -eq 0 ] && return 0
  ry_die "railyard needs ${missing[*]}, and $([ ${#missing[@]} -eq 1 ] && echo "it is" || echo "they are") not on PATH. Install with 'brew install ${missing[*]}' or 'apt install ${missing[*]}'."
}

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

# --- DDEV -------------------------------------------------------------------
# Two sidings of the same project cannot both run `ddev` under one project
# name, and neither can a siding and Mark's own checkout. The fix is one line
# of per-siding config: a unique `name:` in .ddev/config.local.yaml, written at
# couple time so no engine ever has to discover it. The file is gitignored in
# every project, so it never shows up in the siding's diff.

RY_DDEV_OVERRIDE=".ddev/config.local.yaml"

ry_prefix_valid() {  # <token>: one hostname-label-safe word
  [[ $1 =~ ^[A-Za-z0-9][A-Za-z0-9-]*$ ]]
}

RY_DDEV_NAME_MAX=63   # a DDEV project name has to be a valid hostname label

ry_ddev_name() {  # <prefix> <project> -> the name, or 1 when it does not fit
  # No truncation: two prefixes differing only past the limit would cut down to
  # one DDEV project name, which is the collision this whole change exists to
  # prevent. A prefix that long is a mistake worth naming, so it is refused at
  # dispatch time (see ry-dispatch.sh) and refused again here.
  local n="$1-$2"
  [ ${#n} -le $RY_DDEV_NAME_MAX ] || return 1
  printf '%s\n' "$n"
}

ry_ddev_name_too_long() {  # <prefix> <project>: message for a name that will not fit
  printf "'%s-%s' is %d characters; a DDEV project name is a hostname label, so it cannot exceed %d. Use a shorter --prefix (a ticket number, or one short word)." \
    "$1" "$2" "$((${#1} + 1 + ${#2}))" "$RY_DDEV_NAME_MAX"
}

ry_ddev_write_override() {  # <siding> <project> <prefix>: no-op without .ddev/
  local siding=$1 project=$2 prefix=$3 name
  [ -d "$siding/.ddev" ] || return 0
  git -C "$siding" check-ignore -q -- "$RY_DDEV_OVERRIDE" || ry_die \
    "project '$project' does not gitignore $RY_DDEV_OVERRIDE. Railyard writes that file into every siding of a DDEV project to give it its own DDEV project name; if the project tracks it, the siding is dirty from the moment it is cut and ry-pr.sh will later refuse to open the PR. Add $RY_DDEV_OVERRIDE to the project's .gitignore, then couple again."
  name=$(ry_ddev_name "$prefix" "$project") \
    || ry_die "cannot name this siding's DDEV project: $(ry_ddev_name_too_long "$prefix" "$project")"
  cat > "$siding/$RY_DDEV_OVERRIDE" <<YAML || return 1
# Written by railyard when this siding was coupled. Gitignored, never committed.
# Its own DDEV project name, so this siding does not clash with another siding
# of $project or with your own checkout.
name: $name
YAML
  printf '%s\n' "$name"
}

ry_ddev_delete() {  # <siding>: remove the siding's DDEV project; never fatal
  local siding=$1 name
  [ -d "$siding/.ddev" ] || return 0
  # A siding cut before railyard wrote overrides has .ddev/ and no override:
  # nothing of ours to delete, and decouple must still reach the worktree.
  [ -f "$siding/$RY_DDEV_OVERRIDE" ] || return 0
  name=$(sed -n 's/^name: *//p' "$siding/$RY_DDEV_OVERRIDE" | head -n 1)
  [ -n "$name" ] || return 0
  if ! command -v ddev >/dev/null 2>&1; then
    printf 'note: ddev is not on PATH; DDEV project %s left in place\n' "$name" >&2
    return 0
  fi
  # --yes: `ddev delete` prompts for confirmation, and redirecting its output
  # does not close stdin, so without this a decouple sits there forever.
  ( cd "$siding" && ddev delete --omit-snapshot --yes "$name" ) >/dev/null 2>&1 \
    || printf 'note: ddev delete --omit-snapshot --yes %s failed; that DDEV project may still exist\n' "$name" >&2
  return 0
}
