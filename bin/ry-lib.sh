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
  cat > "$siding/$RY_DDEV_OVERRIDE" <<YAML || ry_die \
    "could not write $siding/$RY_DDEV_OVERRIDE, so this siding has no DDEV project name of its own and would collide with every other siding of '$project'. The siding is being rolled back; check the permissions on $siding/.ddev and couple again."
# Written by railyard when this siding was coupled. Gitignored, never committed.
# Its own DDEV project name, so this siding does not clash with another siding
# of $project or with your own checkout.
name: $name
YAML
  printf '%s\n' "$name"
}

ry_ddev_resolve_name() {  # <siding> [<prefix>] [<project>] -> the DDEV project name
  # Three sources, best first. The override is what couple wrote. Rebuilding it
  # from the task's meta covers a siding cut before railyard wrote overrides at
  # all. The project's own .ddev/config.yaml is the last resort: it is the name
  # ddev would have used, so it is the one that exists if nothing overrode it.
  local siding=$1 prefix=${2:-} project=${3:-} name=""
  if [ -f "$siding/$RY_DDEV_OVERRIDE" ]; then
    name=$(sed -n 's/^name: *//p' "$siding/$RY_DDEV_OVERRIDE" | head -n 1) || name=""
  fi
  if [ -z "$name" ] && [ -n "$prefix" ] && [ -n "$project" ]; then
    name=$(ry_ddev_name "$prefix" "$project") || name=""
  fi
  if [ -z "$name" ] && [ -f "$siding/.ddev/config.yaml" ]; then
    name=$(sed -n 's/^name: *//p' "$siding/.ddev/config.yaml" | head -n 1) || name=""
  fi
  printf '%s\n' "$name"
}

ry_ddev_delete() {  # <siding> [<prefix>] [<project>]: never fatal, never blocking
  # .ddev/ is the trigger, not the override file: a siding cut before railyard
  # wrote overrides still has a DDEV project, and it still has to go. Every
  # step here is tolerant, because the caller runs under set -euo pipefail and
  # a decouple must never be stopped by the state of a DDEV project.
  local siding=$1 name
  [ -d "$siding/.ddev" ] || return 0
  name=$(ry_ddev_resolve_name "$siding" "${2:-}" "${3:-}") || name=""
  if [ -z "$name" ]; then
    printf 'note: %s has .ddev/ but no DDEV project name could be worked out; nothing deleted\n' "$siding" >&2
    return 0
  fi
  if ! command -v ddev >/dev/null 2>&1; then
    printf 'note: ddev is not on PATH; DDEV project %s left in place\n' "$name" >&2
    return 0
  fi
  # --yes skips the confirmation prompt (redirecting output does not close
  # stdin, so without it a decouple sits there forever); --omit-snapshot skips
  # the snapshot. Same pair as ddev's own -yO.
  ( cd "$siding" && ddev delete --omit-snapshot --yes "$name" ) >/dev/null 2>&1 \
    || printf 'note: ddev delete --omit-snapshot --yes %s failed; that DDEV project may still exist\n' "$name" >&2
  return 0
}

# --- events -----------------------------------------------------------------

ry_event() {  # <id> <text>: one line on state/events.log
  # The watcher turns each new line into an inbox line for the yardmaster.
  # There is exactly one such channel; anything the yardmaster must see without
  # polling goes through here.
  local home; home=$(ry_home)
  printf '%s %s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" >> "$home/state/events.log"
}

# --- worktree start script --------------------------------------------------
# A project can set up a freshly cut siding for itself: a database, a warmed
# environment, whatever the engine would otherwise have to improvise. The
# script is found at a fixed path inside the project repo or not at all --
# nothing declares it. It runs at couple time, after the DDEV name override so
# it can reach `ddev`, and before the engine launches.
#
# Its contract lives in docs/guide.md ("The worktree start script"). Keep the
# two in step: whoever writes the first one reads that page and nothing else.

RY_START_SCRIPT=".railyard/worktree-start.sh"
# The bound, and the fallback when RY_START_TIMEOUT is unusable. Both are
# overridable so the test suite can prove the watchdog fires without sitting
# here for ten minutes; there is no reason to set either by hand.
RY_START_TIMEOUT_DEFAULT=${RY_START_TIMEOUT_DEFAULT:-600}

ry_fixture_dir() {  # <project> -> fixtures/<project>, created if missing
  local home d; home=$(ry_home); d="$home/fixtures/$1"
  mkdir -p "$d" || ry_die "could not create $d"
  printf '%s\n' "$d"
}

ry_start_outcome=""   # set by ry_run_start_script: "" | "exit N" | "timeout Ns"

# Set ry_start_outcome for the caller (ry-couple.sh) to read; that is a
# cross-file use, which the linter cannot see.
# shellcheck disable=SC2034
ry_run_start_script() {  # <id> <siding> <project>: 1 when the script failed
  # Returns 0 when there is no script at all (the common case, and nothing is
  # written), and 0 when the script succeeded. On failure or timeout it returns
  # 1 with ry_start_outcome set; the caller reports and launches anyway.
  ry_start_outcome=""
  local id=$1 siding=$2 project=$3
  local script="$siding/$RY_START_SCRIPT"
  [ -f "$script" ] || return 0

  local home bindir log secs pid waited rc monitor backend fixtures
  home=$(ry_home); log="$home/state/$id.start.log"
  bindir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

  # A bad bound is worse than no bound: `[ 0 -ge abc ]` errors and stays false,
  # so the watchdog below would never fire and a hanging script would hold the
  # coupling open forever -- the one failure the timeout exists to prevent,
  # reachable by a typo. Fall back to the default, out loud: silently ignoring
  # what someone typed is how you end up debugging the wrong number.
  secs=${RY_START_TIMEOUT:-$RY_START_TIMEOUT_DEFAULT}
  if ! [[ $secs =~ ^[0-9]+$ ]] || [ "$secs" -lt 1 ]; then
    printf 'note: RY_START_TIMEOUT=%s is not a whole number of seconds of at least 1; using %s\n' \
      "$secs" "$RY_START_TIMEOUT_DEFAULT" >&2
    secs=$RY_START_TIMEOUT_DEFAULT
  fi

  backend=$(ry_backend 2>/dev/null || echo none)
  fixtures=$(ry_fixture_dir "$project")
  local -a envv
  envv=(RY_HOME="$home" RY_ID="$id" RY_BIN="$bindir" RY_BACKEND="$backend"
        RY_SIDING="$siding" RY_PROJECT="$project" RY_FIXTURE_PATH="$fixtures")

  # Which interpreter runs it. A `#!` line on an executable file is the
  # project's own choice and is honoured; everything else runs under bash, by
  # name.
  #
  # Naming bash matters. Handing an executable file with no `#!` to exec is not
  # an error: execvp(3) falls back to running it with /bin/sh, which is bash on
  # macOS and dash on Debian and Ubuntu. So a shebang-less start script would
  # get a different shell depending on the machine, and the first bashism in it
  # would fail on Linux only -- which is exactly how this was found.
  local first=""
  local -a runner
  if [ -x "$script" ] && IFS= read -r first < "$script" && [ "${first#\#!}" != "$first" ]; then
    runner=("$script")
  else
    runner=(bash "$script")
  fi

  # Job control gives the script its own process group, so a timeout can kill
  # the whole tree. Without it a hung child of the script would outlive the
  # kill and keep the log open. `timeout(1)` is GNU coreutils and is not on a
  # stock macOS, so the bound is a bash watchdog instead.
  case $- in *m*) monitor=1 ;; *) monitor=0 ;; esac
  set -m
  (
    cd "$siding" || exit 127
    exec env "${envv[@]}" "${runner[@]}"
  ) >"$log" 2>&1 &
  pid=$!
  [ "$monitor" -eq 1 ] || set +m

  waited=0
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$waited" -ge "$secs" ]; then
      kill -TERM "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
      sleep 1
      kill -KILL "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      ry_start_outcome="timeout ${secs}s"
      printf '\n[railyard] killed after %ss: the start script did not exit.\n' "$secs" >> "$log"
      return 1
    fi
    sleep 1
    waited=$((waited + 1))
  done
  rc=0; wait "$pid" 2>/dev/null || rc=$?
  [ "$rc" -eq 0 ] && return 0
  ry_start_outcome="exit $rc"
  return 1
}

ry_start_failure_notice() {  # <id> <outcome> -> the text the engine is given
  local id=$1 outcome=$2 home; home=$(ry_home)
  cat <<TXT
Setup notice: this project's own environment setup script
($RY_START_SCRIPT) failed before you started -- $outcome. Its output is in
$home/state/$id.start.log.

Repairing that script, or working around it, is not your job: the failure has
already been reported to the yardmaster. Do not edit it and do not reinvent
what it does.

Carry on if the task does not need the environment -- a read-only survey
usually does not. If it does need it, stop and report BLOCKED saying so. Never
fabricate a result you could not actually verify.
TXT
}
