# Adding cmux and herdr as railyard backends

*For the dispatcher — a plan, not yet built. Backend design: [`design.md`](design.md#backends).*

Both tools are terminal workspace managers for coding agents, which is exactly
the job the backend seam already does for tmux and Orca. Neither changes what
railyard owns: railyard still cuts its own sidings, writes its own state, and
runs its own watcher. The backend only answers "open a terminal here", "show me
it", "type into it", "close it", and "who am I".

## What a backend has to answer

`bin/ry-backend-lib.sh` is the whole contract — nine functions:

| function | job |
| --- | --- |
| `ry_backend_check` | is this backend usable right now |
| `ry_backend_open <id> <siding> <cmd>` | open a terminal on the siding, return a target |
| `ry_backend_stop <id>` | close it |
| `ry_backend_peek <id>` | recent output |
| `ry_backend_send <id> <text>` | type into it |
| `ry_backend_nudge <text>` | wake the yardmaster |
| `ry_backend_self` | this session's own terminal id |
| `ry_backend_claim_file` | where the yard claim lives |
| `ry_backend_alive <target>` | is that terminal still there |

Plus one case in `bin/ry-yard.sh` to open the yardmaster itself.

## Prerequisite: one claim file (S — ~1h)

`ry_backend_nudge` currently reads `state/yardmaster.pane` and
`state/yardmaster.orca` by name. A third and fourth file makes that a growing
list, and it is already why one yard opened in two backends holds two claims.

Replace the per-backend files with a single `state/yardmaster.claim` holding
`backend=<name>` and `target=<id>`. Then nudge reads one file, and mixing
backends in one yard becomes a collision the session-start hook can report,
instead of a silent double claim.

Do this before either backend. It is small, it is tested by
`tests/ry-session-start.bats`, and both new backends inherit it.

## herdr — effort: S/M (~3–4h)

`herdr` is on `PATH` (v0.8.0) and exposes everything the seam needs over its
socket API, in JSON. It is the closest match to the shape Orca already proved.

| seam function | herdr |
| --- | --- |
| check | `command -v herdr` + `herdr status server` |
| open | `herdr tab create --cwd <siding> --label ry-<id> --env RY_...  --no-focus` → `.result.root_pane.pane_id`, then `herdr pane run <pane> "<cmd>"` |
| stop | `herdr tab close <tab_id>` |
| peek | `herdr pane read <pane> --source recent-unwrapped --lines 200` |
| send | `herdr agent prompt <pane> "<text>"` (bracketed-paste aware), falling back to `herdr pane send-text` |
| nudge | same as send, against the claimed pane |
| self | `$HERDR_PANE_ID` |
| alive | `herdr pane get <pane>` |
| the yard | `herdr tab create --cwd <home> --label yardmaster` + `pane run` |

Why it is cheap:

- native `--env KEY=VALUE` on `tab create`, so `RY_BACKEND` and friends
  propagate without baking exports into the command string;
- every command returns JSON with the ids to use next — no screen scraping;
- `$HERDR_PANE_ID` is injected into every managed pane, so `ry_backend_self`
  is a one-liner;
- `herdr` recognises Claude as an agent kind, so `agent prompt` handles the
  paste semantics that `send-keys` gets wrong.

Two things to record in meta, not one: the pane id (peek/send) and the tab id
(stop). `bin/ry-engine-launch.sh` already writes `backend=` and `target=`; a
`target2=`-style second field or a `tab:<id>/pane:<id>` composite target is the
only state change needed.

Free upside, not in scope: `herdr agent wait --until blocked` would let the
watcher notice a blocked engine without the Stop hook. Leave the status-file
contract alone; note it as a later option.

## cmux — effort: M (~4–6h, includes a spike)

`cmux` ships a full socket CLI with tmux-compatibility commands, so the mapping
is just as clean on paper — the cost is in the unknowns, not the design.

| seam function | cmux |
| --- | --- |
| check | `cmux ping` (the socket, not just the binary) |
| open | `cmux new-workspace --name ry-<id> --cwd <siding> --command "<cmd>" --env RY_... --focus false` |
| stop | `cmux close-workspace --workspace <id>` |
| peek | `cmux capture-pane --workspace <id> --lines 200` |
| send | `cmux send --workspace <id> "<text>"` + `cmux send-key --workspace <id> enter` |
| nudge | same, optionally plus `cmux notify` |
| self | `$CMUX_WORKSPACE_ID` |
| alive | `cmux list-workspaces` contains the id |
| the yard | `cmux <home>` — opens the directory in a new workspace and launches the app if it is not running |

What makes it a step harder than herdr:

1. **The CLI is not on `PATH`.** It lives at
   `/Applications/cmux.app/Contents/Resources/bin/cmux` and is only on `PATH`
   inside cmux's own terminals. Needs an `RY_CMUX_BIN` override with that path
   as the fallback.
2. **Ids vs refs.** cmux prints short refs (`workspace:2`) by default, which are
   positional. Everything stored in meta must use `--id-format uuids`, or a
   closed workspace renumbers the target of a live engine.
3. **Output format is unverified.** The app was not running while this plan was
   written (socket refused), so the exact shape of `new-workspace` output is
   unconfirmed. Budget a short spike: start cmux, run `new-workspace`,
   `capture-pane`, `close-workspace` by hand, and write the parse against what
   they actually print.
4. **Caller context.** `new-workspace` creates "in the caller's window", so the
   watcher — a daemon with no cmux window — may need an explicit `--window`.
   The spike settles this too.

## Test approach (both, included in the estimates)

`tests/fakebin/orca` is the pattern: a shell stub on `PATH` that answers the
handful of commands with canned JSON and logs its arguments. Copy it to
`tests/fakebin/herdr` and `tests/fakebin/cmux`, then mirror `tests/ry-orca.bats`
— open records the right target, stop closes it, peek and send hit the recorded
target, and the yard claim round-trips. No real app needed in CI.

## Suggested order

1. One claim file (S) — unblocks and simplifies both.
2. herdr (S/M) — the cheap one, and it proves the seam holds a third backend.
3. cmux spike, then cmux (M).

Total: roughly two focused sessions.

## The open question

Three backends are supported today with no way to know which one a yard should
use beyond `RY_BACKEND` in the environment. If more than one is normal for you,
`data/` should record a default per yard so `bin/ry-yard.sh` needs no env var.
Worth deciding before the count reaches four.
