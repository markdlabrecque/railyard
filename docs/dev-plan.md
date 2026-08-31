# What is left to build

*For the dispatcher. Six items, none of them blocking anything. Written after
the v0.2.0 release, ordered by how much each one changes a working day rather
than by how hard it is. Backend design: [`design.md`](design.md#backends);
what the backends work already shipped: [`backends-plan.md`](backends-plan.md).*

## 1. `ry-view.sh` — tmux hosts the yard, the other backends look at it

The one that changes daily work. Today a yard runs on one backend and its
terminals live inside that app, so moving from the laptop to something with a
phone in it means moving the yard.

It does not have to. Run the yardmaster and every engine in tmux, and let herdr
or Orca open a single terminal that attaches to it:

```sh
bin/ry-view.sh herdr    # opens one herdr tab running:
                        # tmux -L <socket> new-session -t railyard -s railyard-herdr
```

Why this is the easy version and not the hard one:

- The watcher wakes the yardmaster with `tmux send-keys` at a pane id. That
  works whether anyone is attached or not, so the nudge path does not care who
  is looking.
- Switching viewer changes no railyard state at all. Close the herdr tab, open
  the Orca one. No claim rewrite, no handover, nothing to migrate. The
  yardmaster does not notice.
- `new-session -t` rather than `attach` puts each viewer in its own session in
  a group, so two viewers do not fight over window size or which window is
  current.

What it costs: herdr sees `tmux` in that pane, not `claude`, so its native
agent detection stays dark and `agent prompt` is the wrong call — a viewer
terminal is not an engine and railyard never sends to it. Orca likewise loses
its worktree-terminal features. Neither matters, because railyard's own status
comes from the Stop hook and the inbox.

Effort: S/M, roughly 2–3h with tests. Nothing in the backend seam changes; the
native backends stay for anyone who wants real tabs per engine. The fake CLIs
under `tests/fakebin/` already answer enough to test the open call.

Settle first: whether Orca's mobile view mirrors an arbitrary command terminal,
or only ones it started itself. If it is the latter, this item is tmux + herdr
only, and Orca stays a native backend.

## 2. The split yard — engines are welded to the backend that dispatched them

`bin/ry-engine-launch.sh` writes `backend=` and `target=` into
`state/<id>.meta` at launch, and peek, send and decouple read them for the life
of the task. That is what lets a yardmaster take over on a different backend
without breaking the engines already running.

It is also the trap. Engines dispatched under herdr stay reachable only through
herdr. Quit herdr and they are unreachable, even though their sidings, their
branches and their state are all fine. Dispatch after that and the new engines
open somewhere else, so one yard ends up split across two apps.

Two ways out:

- **Move a running engine.** A live Claude is welded to a PTY the old backend
  owns; the new one cannot adopt it. It means stopping the engine and
  relaunching with `claude --resume`, which needs the session id captured at
  launch and risks the engine's context and its Stop hook. M/L, and lossy.
- **Make item 1 the answer.** If every engine runs in tmux and the other
  backends are only viewports, this never happens.

Recommendation: build item 1, then check whether this still bites. Do not scope
it before then.

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
