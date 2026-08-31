# What was left to build

*For the dispatcher. Six items, written after the v0.2.0 release and ordered by
how much each one changed a working day rather than by how hard it was. All six
are now closed — five built, one dropped — and this file is kept as the record
of what shipped and why. Backend design: [`design.md`](design.md#backends); the
backends work: [`backends-plan.md`](backends-plan.md). Nothing here is pending.*

## 1. `ry-view.sh` — shipped

*Built. `bin/ry-view.sh <herdr|orca|cmux>` opens one terminal in that app
running `tmux new-session -t railyard -s railyard-<backend>`, so the yard stays
in tmux and the other apps are viewports onto it. Covered by
`tests/ry-view.bats`; described in [`guide.md`](guide.md#watching-a-tmux-yard-from-another-app).*

Viewer sessions join the yard's session group, so two viewers do not fight over
window size or which window is current, and they clean themselves up on detach.
A second viewer on the same backend takes `railyard-herdr-2` rather than
stealing the first one's client. `--dry-run` prints the attach command.

The cost is the one the plan predicted: the viewing app sees `tmux` in that
terminal rather than `claude`, so its native agent detection stays dark. That
does not matter — railyard's status comes from the Stop hook and the inbox.

Still unsettled, and left to try rather than to design: whether Orca's mobile
view mirrors an arbitrary command terminal or only ones it started itself. The
`orca` viewer is implemented the same way as the other two; if the mobile view
turns out not to mirror it, that is a limitation of the viewer, not of the
command.

## 2. The split yard — settled

*Checked after item 1 shipped, as this item asked. The lossy option — stopping
a live engine and relaunching it with `claude --resume` on another backend —
was not built, and should not be.*

Item 1 removes the trap for anyone who takes it: host the yard in tmux, look at
it from herdr or Orca, and no engine is ever welded to an app you might quit.
What item 1 does not do is *stop* you hosting a yard in herdr and then
dispatching on tmux, so the trap was still reachable by accident.

That is now refused. `bin/ry-engine-launch.sh` records `backend=` and `target=`
per engine as before; `ry_backend_no_split` in `bin/ry-backend-lib.sh` reads
those back and refuses to open an engine beside engines in another app.
`bin/ry-dispatch.sh` and `bin/ry-couple.sh` both check before they write
anything, so a refused dispatch leaves no half-made task and a refused couple
leaves the siding uncut. `RY_ALLOW_SPLIT=1` overrides it for the case the guard
cannot judge — the other app is already gone and you want to carry on. Covered
by `tests/ry-split-yard.bats`.

So the yard can no longer split by accident, and the way not to want to is item
1. Moving a running engine between backends stays unbuilt, and there is no
longer a reason to build it.

## 3. `ry-claim.sh --held` — shipped

*Built. `bin/ry-claim.sh --held` says nothing and exits 0 when a live terminal
holds the yard, 1 otherwise — including when the claim names a terminal that
has since closed, which is not a held yard. `--json` answers the same question
as `held`, `backend`, `target` and `alive` fields. Covered by
`tests/ry-claim.bats`.*

## 4. A default backend per yard — shipped

*Built. `data/yard.md` records the yard's backend on a `backend:` line;
`ry_backend()` reads it when `RY_BACKEND` is unset, and falls back to `tmux`
when neither says anything. Covered by `tests/ry-yard-backend.bats`; described
in [`guide.md`](guide.md#choosing-this-yards-backend).*

Four backends, and nothing recorded which one a yard should use except
`RY_BACKEND` in whatever shell you happened to be in. Since v0.2.0 a mismatch
was at least *reported* — the claim names its backend and a session on another
one is told to stand down — but you still set the variable by hand every time,
and getting it wrong was a stood-down session rather than a running yard.

It is recorded in the yard now, the way `data/projects.md` records a project's
mode and base, and it cost what the plan predicted: one function plus a file.
The environment still wins over the file, deliberately — the test suite runs on
`RY_BACKEND=none` and every backend test overrides it per file, and a one-off
run in another app should not have to edit the yard.

The one thing added beyond the plan: backend errors now say where the answer
came from (`RY_BACKEND`, `data/yard.md`, or the default), because a typo in a
file you set months ago should not read as a typo in your shell.

## 5. `no-mistakes` delivery mode — dropped

*Decided. `bin/ry-dispatch.sh` refuses `--mode no-mistakes` with a message
naming the modes that work. The mode is gone from the usage line, from
`data/projects.md`, and from the guide. Covered by `tests/ry-dispatch.bats`.*

This was the one item the plan posed as a question rather than a task: decide
what the mode promises, or drop it until it means something. It is dropped.

The problem was never that the mode was unimplemented — plenty is. It was that
dispatch *accepted* it and wrote it into the task's meta, while
`bin/ry-merge-local.sh` takes only `local-only` and `bin/ry-pr.sh` only `pr`.
A no-mistakes haul could be dispatched, run, finish, and then have no way to be
delivered. A mode that can be chosen and not honoured is worse than one that
does not exist, and the fix that costs nothing is to stop accepting it.

What it would have to mean before it comes back: something a delivery mode can
actually gate — a verification pass an engine's own tests do not cover, or a
second engine reviewing the first — not a stricter feeling about the same
merge. Reversing this is a one-line re-add to the `case` in
`bin/ry-dispatch.sh` once that is settled.

## 6. herdr `agent wait --until blocked` — shipped

*Built, narrowly. `ry_backend_blocked()` in `bin/ry-backend-lib.sh` is a
backend question every backend may decline; only herdr answers it, via
`ry_herdr_blocked()`. The watcher uses it to raise its existing "running, and
silent" inbox line at once instead of after `RY_STALL_MIN` minutes. Covered by
`tests/ry-herdr.bats`.*

The plan's warning was the design: one backend knowing better is a reason to
think, not a reason to special-case. The tempting version — let herdr report
turn ends — would have given one backend its own path into the status file, and
the contract's whole value is that every backend writes it the same way.

So the question herdr answers is narrower than the one it *could* answer. Not
"has this engine finished", which is the Stop hook's to answer and stays that
way, but "is this engine sitting at a prompt right now". That changes no state
and adds no event kind; it only decides how quickly an existing inbox line is
raised. Backends that cannot tell return false and the twenty-minute timer does
the work, exactly as before.

Anything unexpected from herdr — an old CLI, a pane it does not treat as an
agent, a socket error — reads as "cannot tell" rather than "blocked", because a
false blocked would wake the yardmaster about an engine that is working.
