# Railyard: a guide for the dispatcher

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
attaches to the existing session rather than starting a second one. A hook
records the pane, starts the watcher daemon, and hands the yardmaster a summary
of where things stand.

Leave it running. The watcher is what makes the whole thing event-driven — when
an engine finishes, it pokes the yardmaster's pane. Nothing polls.

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
`tmux capture-pane -p -t railyard:ry-<id>`.

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
| `bin/ry-dispatch.sh --haul\|--survey [--mode <m>] [--base <b>] [--after <id>] <project> "<waybill>"` | dispatch or queue a task |
| `bin/ry-manifest.sh` | every task not yet decoupled |
| `bin/ry-inbox.sh [--ack]` | unread engine events |
| `bin/ry-deps.sh <id>` | is a queued task ready, pending, or stranded |
| `bin/ry-couple.sh <id>` | cut a queued task's siding by hand |
| `bin/ry-review-diff.sh <id>` | an engine's commits and diff |
| `bin/ry-merge-local.sh [--push] <id>` | fast-forward the base branch |
| `bin/ry-pr.sh <id>` | open the PR/MR |
| `bin/ry-pr-poll.sh <id>` | check an open PR once, by hand |
| `bin/ry-decouple.sh [--force] [--delete-branch] <id>` | remove the siding, archive the state |

`ry-dispatch.sh` and `ry-decouple.sh` take `-h`; every other script documents
its usage in the comment at the top of the file.

## Shutting down

```sh
tmux kill-session -t railyard
kill "$(cat state/.watch.lock)"
```

The watcher restarts itself next time you open the yard.
