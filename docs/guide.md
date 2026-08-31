# Railyard: a guide for the dispatcher

*For the human. Agents get their instructions from [`../AGENTS.md`](../AGENTS.md)
and do not need this file.*

Railyard runs Claude Code agents on your repos, one isolated git worktree per
task, and keeps you in the loop for every decision that matters. You are the
**dispatcher**. The session you talk to is the **yardmaster**. It reads your
projects and never edits them — every change is an **engine's** job.

Vocabulary is in [`../CONTEXT.md`](../CONTEXT.md); why it works this way is in
[`design.md`](design.md). This is how to use it.

## Open the yard

```sh
bin/ry-yard.sh
```

A tmux session `railyard` with the yardmaster in window `yard`. Re-running
attaches to the existing session rather than starting a second one. To run the
yard in Orca instead, see [Running in Orca](#running-in-orca). A hook
records the pane, starts the watcher daemon, and hands the yardmaster a summary
of where things stand.

Leave it running. The watcher is what makes the whole thing event-driven — when
an engine finishes, it pokes the yardmaster's pane. Nothing polls.

One session holds the yard at a time. Start a second Claude session in this
folder and it is told another yardmaster holds it, and stands down — otherwise
the two would share one inbox and take work from each other.

## Running a second yard

A yard is a clone. Clone railyard again and it is a separate yard — its own
projects, sidings, state, watcher and inbox. Give it its own tmux session:

```sh
cd ~/yards/beta
RY_TMUX_SESSION=beta bin/ry-yard.sh
```

Without that, both yards fight over the session named `railyard` and beta's
engines open windows in alpha. `bin/ry-yard.sh --dry-run` shows what would
start. Do not register the same project in two yards.

## Running in Orca

tmux is the default; Orca, cmux and herdr are the other supported
**backends** — the thing that hosts terminals. Railyard still owns everything
that matters (sidings, state, the watcher, the inbox); the backend only decides
what window an engine appears in.

Needs the `orca` CLI on your `PATH`, with Orca running, plus `jq`.

```sh
RY_BACKEND=orca bin/ry-yard.sh
```

That registers this repo with Orca if it is not already, then opens a focused
Orca terminal titled `yardmaster` running Claude here. `RY_BACKEND` travels into
that session, so every engine it dispatches opens in Orca too — you never set it
again. Put it in your shell profile if Orca is your normal way to work.

Each engine gets its own Orca terminal titled `ry-<id>`, opened on its siding as
an external worktree. Decoupling stops that terminal.

Nothing about the daily loop changes. The only differences:

| | tmux | Orca | cmux | herdr |
| --- | --- | --- | --- | --- |
| the yard | session `railyard`, window `yard` | terminal `yardmaster` | workspace `yardmaster` | tab `yardmaster` |
| an engine | window `ry-<id>` | terminal `ry-<id>` | workspace `ry-<id>` | tab `ry-<id>` |
| the yard claim | `$TMUX_PANE` | `$ORCA_TERMINAL_HANDLE` | `$CMUX_WORKSPACE_ID` | `$HERDR_PANE_ID` |
| shutting down | `tmux kill-session -t railyard` | close the terminals in Orca | close the workspaces in cmux | close the tabs in herdr |

Use `bin/ry-peek.sh <id>` and `bin/ry-send.sh <id> "<text>"` to look at or talk
to an engine — they read the backend out of the task's own state, so they work
the same either way. Reach for `tmux` commands directly only on a tmux yard.

Whichever backend you use, the claim lands in one file,
`state/yardmaster.claim`, naming the backend and the terminal:

```
backend=tmux
target=%3
```

`bin/ry-claim.sh` shows who holds it, and hands it over when the automatic
check gets it wrong:

```sh
bin/ry-claim.sh                    # who holds the yard, and is that terminal still there
bin/ry-claim.sh --held             # no output; exit 0 if a live terminal holds it
bin/ry-claim.sh --json             # the same answer as fields
bin/ry-claim.sh --release          # drop it, so the next session to start takes over
bin/ry-claim.sh --take             # claim it for this session
```

`--held` is the one for a shell prompt or a script — it answers with an exit
code and says nothing, and a claim on a terminal that has since closed counts
as not held. `--json` gives `held`, `backend`, `target` and `alive` for anything
that has to parse the answer.

A claim whose terminal has closed is dropped or taken freely — that is the
normal case, and session start already handles it for you. The one to reach for
this over is the agent that quit while its terminal stayed open: the claim
still reads alive, so add `--force`.

So a yard picks a backend and stays on it. Start a session on a different
backend while another holds the yard and it is told so at session start and
stands down, rather than quietly claiming alongside it and sharing the inbox.

Engines are held to the same rule, and this one is enforced rather than
reported. An engine records the backend that launched it and can only ever be
peeked at, sent to or decoupled through that app, so a yard with engines in two
apps has engines that go dark the moment one of them is quit. Dispatching or
coupling onto a second backend is refused:

```
error: this yard already has engines on herdr (xyz-0830-1412-3f9a), and tmux
would split it. ...
```

Decouple those tasks first, or open the yard on the backend they are already
on — or take the third option and host every engine in tmux, looking at it from
the other app with `bin/ry-view.sh`. `RY_ALLOW_SPLIT=1` overrides the refusal
for the case where the other app is gone and you want to carry on regardless.

## Running in cmux

```sh
RY_BACKEND=cmux bin/ry-yard.sh
```

One cmux workspace per engine, named `ry-<id>`, opened on its siding. Same loop,
same commands — see the table above for what changes.

Two things worth knowing:

- **The CLI is not on your `PATH`.** It lives inside the app bundle, and
  railyard falls back to
  `/Applications/cmux.app/Contents/Resources/bin/cmux` when `cmux` is not
  found. `RY_CMUX_BIN` overrides that.
- **cmux only accepts control from processes started inside cmux.** A yard
  *hosted* in cmux satisfies that on its own — the watcher inherits the socket
  credentials from the yardmaster that started it. Driving cmux from a yard
  hosted elsewhere needs `socketControlMode` raised from `cmuxOnly` in
  `~/.config/cmux/cmux.json`; `RY_CMUX_PASSWORD` is passed through for the
  password mode.

## Running in herdr

```sh
RY_BACKEND=herdr bin/ry-yard.sh
```

One herdr tab per engine, labelled `ry-<id>`, opened on its siding. Same loop,
same commands — see the table above for what changes.

Two things worth knowing:

- **herdr needs its server running.** `bin/ry-yard.sh` and every dispatch check
  `herdr status server` first and refuse early rather than half-open a task.
  Start it by running `herdr` once.
- **A task's `target` holds two ids**, written `tab:<tab_id>/pane:<pane_id>`.
  The pane is what peek and send talk to; the tab is what decouple closes.
  Nothing else in railyard has to care, but that is why the field looks
  different from the other backends'.

## Watching a tmux yard from another app

The backends above each host a whole yard. There is a second way to use them:
run the yard in tmux and let one of the others just *look* at it.

```sh
bin/ry-view.sh herdr      # one herdr tab attached to the tmux yard
bin/ry-view.sh orca
bin/ry-view.sh cmux
```

Each opens a single terminal running

```
tmux new-session -t railyard -s railyard-herdr
```

so the viewer joins the yard's session group — its own session, its own window
size, the same windows. `--dry-run` prints that command without opening
anything.

Why this is worth having: the yardmaster and every engine stay in tmux, so the
watcher's nudge works whether anyone is attached or not, and switching viewer
changes no railyard state at all. Close the herdr tab, open the Orca one; no
claim rewrite, no handover, nothing to migrate. The yardmaster does not notice.
It also means the yard cannot get split across two apps: engines are only ever
launched by the tmux yard.

What it costs: the viewing app sees `tmux` in that terminal, not `claude`, so
its native agent detection stays dark and its worktree-terminal features do not
apply. That is fine — a viewer is not an engine. Railyard records no state for
it, never sends to it, and the yardmaster's status comes from the Stop hook and
the inbox either way.

Viewer sessions clean themselves up on detach, and a second viewer on the same
backend gets `railyard-herdr-2` rather than stealing the first one's client.

## Register a project

```sh
git clone <url> projects/<name>
```

Then add a line to [`../data/projects.md`](../data/projects.md):

```
- `myapp` — pr, base: develop, notes: main repo
```

`name` must match the directory under `projects/`. Both other fields are
optional:

- **mode** — how finished hauls are delivered: `local-only`, `pr`, or
  `no-mistakes`. Defaults to `local-only`.
- **base** — the branch sidings are cut from and merged back into. Defaults to
  `develop` when the project has one, otherwise the remote's default branch.
  Railyard never touches your release branch.

## The daily loop

**Ask for work.** Plain language is enough. `/dispatch myapp fix the flaky
login test` dispatches one engine; describing several tasks dispatches several.

The yardmaster decides two things per task and tells you what it picked:

- **shape** — `haul` changes code and ships it; `survey` is read-only and
  writes a report to `data/<id>/report.md`.
- **mode** — from the project's registered mode. Say "use local-only for this
  one" to override.

**Wait.** The turn ends. You get on with your day. When the engine finishes,
the watcher wakes the yardmaster with the engine's own one-line handoff.

**Review.** The yardmaster reads the diff (`bin/ry-review-diff.sh <id>`) or the
survey report, judges it against the waybill, and brings you the outcome plus
the one decision you need to make.

That decision is always yours. `DONE` from an engine is a claim, not an
approval. Merging, pushing, dropping work, and decoupling a siding with
uncommitted changes each need your explicit word, for that specific task.

**Deliver.** On your word:

| mode | what happens |
| --- | --- |
| `local-only` | `bin/ry-merge-local.sh [--push] <id>` — fast-forwards the base branch in your clone |
| `pr` | `bin/ry-pr.sh <id>` — pushes the branch, opens the PR/MR, then the watcher polls CI and tells you when it merges or the checks fail |
| survey | nothing to merge; the findings are the deliverable |

**Decouple.** `bin/ry-decouple.sh [--delete-branch] <id>` kills the window,
removes the siding, and archives the state.

## Batches that depend on each other

Dispatch a ticket that cannot start until another has landed with `--after`:

```sh
bin/ry-dispatch.sh --haul --after <blocker-id> myapp "<waybill>"
```

It is recorded `queued` — no siding, no engine — and waits. Once every blocker
is **merged into the base branch**, the watcher cuts its siding and starts its
engine on its own, then tells you it did. Chains run all the way down without
you.

The block lifts on the merge, not when the blocker's engine says `DONE`. That
means a batch pauses until you approve each merge — which is the point.

You can chain several: `--after <id1>,<id2>`.

## Seeing where things are

`/manifest` shows every task not yet decoupled, grouped by status, with what
each queued task is waiting on:

```
QUEUED
  myapp-0830-1244-6a3d  myapp  haul  pr  4m
      waiting on myapp-0830-1244-994b
RUNNING
  myapp-0830-1244-994b  myapp  haul  pr  9m
inbox: 0 unread
```

The **inbox** is engine events you have not acted on yet. The yardmaster's turn
is blocked while any line is unread — deliberately. Nothing falls through.

Two more session commands:

- `/allaboard` — recap of the session and any open decisions.
- `/shed` — end-of-session sweep; durable lessons land in `data/learnings.md`.

## When something goes wrong

**`engine <id> silent for Nm`** — a running engine ended no turn. Look at it:
`bin/ry-peek.sh <id>`.

**`engine <id> blocked-stranded <blocker>`** — you decoupled a blocker that
never merged, so nothing behind it can ever unblock. It is never started
silently. Drop the task, or re-dispatch it without that blocker.

**`local <base> has diverged from origin/<base>`** — your clone has unpushed
merges *and* origin has moved. Railyard will not guess which you meant.
Reconcile `projects/<name>` by hand and the queue carries on.

**An engine did the wrong thing** — say so. The yardmaster sends follow-up
instructions into the engine's window; it keeps its context and carries on.

## Command reference

| command | does |
| --- | --- |
| `bin/ry-yard.sh` | open or attach to the yard |
| `bin/ry-view.sh [--dry-run] <herdr\|orca\|cmux>` | open a viewer onto a tmux-hosted yard |
| `bin/ry-dispatch.sh --haul\|--survey [--mode <m>] [--base <b>] [--after <id>] <project> "<waybill>"` | dispatch or queue a task |
| `bin/ry-manifest.sh` | every task not yet decoupled |
| `bin/ry-inbox.sh [--ack]` | unread engine events |
| `bin/ry-deps.sh <id>` | is a queued task ready, pending, or stranded |
| `bin/ry-couple.sh <id>` | cut a queued task's siding by hand |
| `bin/ry-peek.sh <id>` | recent output from an engine's terminal |
| `bin/ry-send.sh <id> "<text>"` | send follow-up text to an engine |
| `bin/ry-review-diff.sh <id>` | an engine's commits and diff |
| `bin/ry-merge-local.sh [--push] <id>` | fast-forward the base branch |
| `bin/ry-pr.sh <id>` | open the PR/MR |
| `bin/ry-pr-poll.sh <id>` | check an open PR once, by hand |
| `bin/ry-decouple.sh [--force] [--delete-branch] <id>` | remove the siding, archive the state |
| `bin/ry-claim.sh [--held\|--json\|--release\|--take] [--force]` | look at, test, drop or take the yard claim |

Every script takes `-h`.

## Shutting down

```sh
tmux kill-session -t railyard   # on Orca: close the terminals in Orca
kill "$(cat state/.watch.lock)"
```

The watcher restarts itself next time you open the yard.
