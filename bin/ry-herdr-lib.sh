#!/usr/bin/env bash
# herdr backend primitives. Railyard keeps its own sidings; herdr just hosts
# the terminal: one herdr tab per engine, created on the siding with `herdr tab
# create --cwd <siding> --label ry-<id>`, then the engine command started in
# that tab's root pane with `herdr pane run`. Inside herdr panes HERDR_PANE_ID
# names the yardmaster's own pane.
#
# Two ids matter and neither can stand in for the other: the pane is what you
# read from and type into, the tab is what you close. Both travel in one
# `target=` field as `tab:<tab_id>/pane:<pane_id>` so nothing else in railyard
# has to learn about a second id.
#
# Every herdr api subcommand answers with the socket API's JSON envelope —
# {"id":...,"result":{...}} on success, {"id":...,"error":{...}} on failure —
# so no output is ever screen-scraped.

ry_herdr_available() {  # is the CLI there at all
  command -v herdr >/dev/null 2>&1
}

ry_herdr_running() {  # is a herdr server up to talk to
  ry_herdr_available &&
    [ "$(herdr status server --json 2>/dev/null | jq -r '.running' 2>/dev/null)" = true ]
}

ry_herdr_ok() {  # <json>: fail with herdr's message when it answered with an error
  jq -e 'has("result")' <<<"$1" >/dev/null 2>&1 ||
    ry_die "herdr: $(jq -r '.error.message // .error.code // "unknown error"' <<<"$1" 2>/dev/null)"
}

ry_herdr_target() {  # <tab> <pane> -> the composite target stored in meta
  printf 'tab:%s/pane:%s\n' "$1" "$2"
}

ry_herdr_pane() {  # <target> -> the pane id (a bare pane id passes through)
  case $1 in */pane:*) printf '%s\n' "${1##*/pane:}" ;; *) printf '%s\n' "$1" ;; esac
}

ry_herdr_tab() {  # <target> -> the tab id
  local t=${1#tab:}
  printf '%s\n' "${t%%/pane:*}"
}

ry_herdr_open() {  # <label> <cwd> <command> -> target
  local out tab pane
  out=$(herdr tab create --cwd "$2" --label "$1" --no-focus)
  ry_herdr_ok "$out"
  tab=$(jq -r '.result.tab.tab_id // empty' <<<"$out")
  pane=$(jq -r '.result.root_pane.pane_id // empty' <<<"$out")
  { [ -n "$tab" ] && [ -n "$pane" ]; } || ry_die "herdr: created a tab for $1 but it named no pane"
  ry_herdr_ok "$(herdr pane run "$pane" "$3")"
  ry_herdr_target "$tab" "$pane"
}

ry_herdr_close() {  # <target>
  herdr tab close "$(ry_herdr_tab "$1")" >/dev/null 2>&1 || true
}

ry_herdr_read() {  # <target> -> recent terminal text
  local out
  out=$(herdr pane read "$(ry_herdr_pane "$1")" --source recent-unwrapped --lines 200)
  ry_herdr_ok "$out"
  jq -r '.result.read.text // empty' <<<"$out"
}

ry_herdr_send() {  # <target> <text>
  # `agent prompt` knows Claude's bracketed-paste semantics; a pane that herdr
  # has not recognised as an agent yet still takes literal text plus Enter.
  local pane out; pane=$(ry_herdr_pane "$1")
  out=$(herdr agent prompt "$pane" "$2" 2>/dev/null) &&
    jq -e 'has("result")' <<<"$out" >/dev/null 2>&1 && return 0
  ry_herdr_ok "$(herdr pane send-text "$pane" "$2")"
  ry_herdr_ok "$(herdr pane send-keys "$pane" enter)"
}

ry_herdr_alive() {  # <target>
  herdr pane get "$(ry_herdr_pane "$1")" 2>/dev/null | jq -e 'has("result")' >/dev/null 2>&1
}
