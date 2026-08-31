# What is left to build

*For the dispatcher. Six items, none of them blocking anything. Written after
the v0.2.0 release, ordered by how much each one changes a working day rather
than by how hard it is. Backend design: [`design.md`](design.md#backends);
what the backends work already shipped: [`backends-plan.md`](backends-plan.md).*

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

## 3. `ry-claim.sh --held`

An exit code rather than a sentence: 0 when a live terminal holds the yard, 1
otherwise, no output. For shell prompts and scripts that want to know before
they act. `--json` alongside it if anything ever needs the backend and target
as fields.

Effort: S, under an hour. `bin/ry-claim.sh` and `tests/ry-claim.bats`.

## 4. A default backend per yard

Four backends, and nothing records which one a yard should use except
`RY_BACKEND` in whatever shell you happen to be in. Since v0.2.0 a mismatch is
at least *reported* — the claim names its backend and a session on another one
is told to stand down — but you still set the variable by hand every time, and
getting it wrong is a stood-down session rather than a running yard.

Record it in the yard instead, the way `data/projects.md` records a project's
mode and base. `ry_backend()` in `bin/ry-backend-lib.sh` is the only place that
reads the default, so this is one function plus a file.

Keep the environment winning over the file: the test suite sets
`RY_BACKEND=none` and every backend test overrides it per file.

Effort: S, 1–2h.

## 5. `no-mistakes` delivery mode

`bin/ry-dispatch.sh` accepts `--mode no-mistakes` and writes it into the task's
meta. Nothing downstream implements it: `bin/ry-merge-local.sh` refuses any
mode but `local-only`, and `bin/ry-pr.sh` handles `pr`. So the mode can be
dispatched and then cannot be delivered.

That is the whole problem, and it is a design question before it is a coding
one: decide what the mode promises, or drop it from the usage line and the
validation until it means something.

Effort: unknown until it is defined.

## 6. herdr `agent wait --until blocked`

herdr can tell the watcher an engine has gone blocked without going through the
Stop hook. Noted while building the herdr backend and deliberately left alone —
the status-file contract is the same for every backend, and one backend knowing
better is a reason to think, not a reason to special-case. An option, not a
pending task.
