#!/usr/bin/env bash
# Orca backend primitives. Railyard keeps its own sidings; Orca just hosts the
# terminal: the project clone is registered as an Orca repo once, after which
# Orca sees each siding as an external worktree and `terminal create
# --worktree path:<siding>` opens a visible terminal there. Inside Orca
# terminals ORCA_TERMINAL_HANDLE names the yardmaster's own terminal.

ry_orca_ok() {  # <json>: fail with Orca's message when ok=false
  [ "$(jq -r '.ok' <<<"$1" 2>/dev/null)" = true ] || ry_die "orca: $(jq -r '.error.message // .error.code // "unknown error"' <<<"$1" 2>/dev/null)"
}

ry_orca_ensure_repo() {  # <repo-dir>: register with Orca if not already
  local out
  out=$(orca repo list --json 2>/dev/null) || ry_die "orca CLI failed; is Orca running?"
  if ! jq -e --arg p "$1" '.result.repos[]? | select(.path == $p)' <<<"$out" >/dev/null; then
    ry_orca_ok "$(orca repo add --path "$1" --json)"
  fi
}

ry_orca_open() {  # <title> <siding> <command> -> handle
  # Orca resolves --worktree path:<siding> against a worktree index it builds
  # asynchronously, so `terminal create` for a siding cut moments earlier can
  # answer selector_not_found even though the siding is real -- a race, not a
  # real error. Retry it (3 attempts total), re-probing the index between
  # tries so the retry is actually waiting on something rather than just
  # hoping. Any other error code is real on the first try, so it fails there.
  #
  # The CLI exits 1 on failure. A bash function inherits errexit from
  # whatever sourced it, not its own setting, so a bare `out=$(orca ...)`
  # here would abort the whole retry loop -- and the calling script with it
  # -- on attempt 1 of a race this loop exists to survive. `|| true` on both
  # reads keeps the failure inside the loop, where the ok/error.code checks
  # below decide whether it is worth a retry.
  local out attempt code
  for attempt in 1 2 3; do
    out=$(orca terminal create --worktree "path:$2" --title "$1" --command "$3" --json) || true
    [ "$(jq -r '.ok' <<<"$out" 2>/dev/null)" = true ] && break
    code=$(jq -r '.error.code // empty' <<<"$out" 2>/dev/null) || true
    [ "$code" = selector_not_found ] && [ "$attempt" -lt 3 ] || break
    orca worktree list --json >/dev/null 2>&1 || true
    sleep "${RY_ORCA_RETRY_SLEEP:-2}"
  done
  ry_orca_ok "$out"
  jq -r '.result.terminal.handle // .result.handle // empty' <<<"$out"
}

ry_orca_stop_siding() {  # <siding>
  orca terminal stop --worktree "path:$1" --json >/dev/null 2>&1 || true
}

ry_orca_send() {  # <handle> <text>
  ry_orca_ok "$(orca terminal send --terminal "$1" --text "$2" --enter --json)"
}

ry_orca_read() {  # <handle> -> tail lines
  orca terminal read --terminal "$1" --json | jq -r '.result.terminal.tail[]? // empty'
}
