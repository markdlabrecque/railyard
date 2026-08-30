# Railyard design

Railyard is a personal agent distro: a folder of instructions, bash scripts,
and state that turns Claude Code into a dispatcher that runs worker agents in
git worktrees. Built for one user. Inspired by firstmate (MIT); specific
scripts may be ported with attribution in the file header.

## Scope (v1)

In:
- Harness: Claude Code only.
- Backend: tmux (reference). Orca behind the same seam later.
- Worktrees: plain `git worktree add` under `yard/<project>/<id>/`. No treehouse.
- Delivery modes per task: `local-only` (fast-forward merge on approval),
  `pr` (open a PR, watch CI), `no-mistakes` (reserved; wired when installed).
- Two task shapes: **haul** (changes a project, ships) and **survey**
  (read-only investigation, writes a report, never pushes).
- Supervision: event-driven watcher (Claude Code Stop hook writes a status
  file; a tiny bash daemon reads it and wakes the yardmaster). Zero tokens
  while idle.
- Tests: bats + shellcheck.

Out:
- Other harnesses (codex, grok, pi, kimi, cursor, opencode).
- Other backends (herdr, zellij, cmux) unless later wanted.
- Secondmates / remote homes, Relay (X/Discord), voice, AFK digests.

## Vocabulary

| firstmate      | railyard      | meaning                                  |
| -------------- | ------------- | ---------------------------------------- |
| captain        | dispatcher    | you                                      |
| first mate     | yardmaster    | the main Claude Code session             |
| crewmate       | engine        | one worker agent                         |
| spawn          | dispatch      | start a worker                           |
| worktree       | siding        | isolated checkout for one task           |
| brief          | waybill       | task instructions handed to an engine    |
| ship task      | haul          | task that changes and delivers code      |
| scout task     | survey        | read-only investigation, report only     |
| teardown       | decouple      | kill session, remove siding              |
| bearings       | manifest      | queued + in-flight tasks (departures board) |
| stow           | shed          | end-of-session knowledge sweep           |
| ahoy           | allaboard     | session recap / open decisions           |

Script prefix: `ry-`. Env prefix: `RY_`. Home: the repo root (`RY_HOME`).

## Base branches

Sidings are cut from, and merged back into, a project's **base branch** —
`develop` by default. Resolution order: `--base` on dispatch, then `base:` on
the project's `data/projects.md` line, then `develop` if the project has one,
then the remote's default branch. Railyard never touches the release branch;
releases are cut outside it and are not represented here.

## Layout

```
railyard/
  AGENTS.md            always-loaded operating contract (short; routes to skills)
  CLAUDE.md            -> AGENTS.md
  bin/                 ry-*.sh scripts, one job each, *-lib.sh for shared code
  .claude/
    settings.json      hooks: SessionStart -> ry-session-start, Stop -> ry-turnend-guard
    skills/            /board /shed /allaboard /dispatch
  projects/            clones of your repos (gitignored)
  yard/                worktrees: yard/<project>/<id>/ (gitignored)
  data/                durable: projects.md, dispatcher.md, learnings.md, <id>/report.md
  state/               volatile: <id>.status <id>.meta manifest.md .watch.lock (gitignored)
  tests/               bats
  docs/
```

## Core loop (tracer bullet)

1. You: "fix the flaky login test in xyz".
2. Yardmaster runs `ry-dispatch.sh --haul --mode pr xyz "<waybill>"`:
   - `git worktree add yard/xyz/<id> -b ry/<id>` from the fresh base branch
   - writes `state/<id>.meta`, `state/<id>.status=running`
   - opens tmux window `ry-<id>`, cwd = siding, runs `claude -p` with the
     waybill; the engine's Stop hook writes `state/<id>.status=turn-ended`
3. `ry-watch.sh` (daemon, started by SessionStart hook) sees the status
   change and injects one line into the yardmaster's tmux pane:
   `engine <id> turn-ended: <one-line summary>`.
4. Yardmaster reviews the diff (`ry-review-diff.sh <id>`), then per mode:
   - `local-only`: asks you, then `ry-merge-local.sh <id>` (ff-only)
   - `pr`: `ry-pr.sh <id>` opens PR; `ry-pr-poll.sh` watches CI
5. `ry-decouple.sh <id>`: kill window, remove worktree, archive meta.

## The queue

A batch of tickets is rarely independent. `--after <id>[,<id>...]` on dispatch
records those ids as the task's **blockers**: it skips step 2's worktree and
engine, is recorded `queued`, and waits.

A block lifts when its blocker is **merged into the base branch**, never when
the blocker's engine finishes. A `DONE` verdict is the engine's claim; the merge
is the fact. This keeps the queue inside the authority rules — nothing proceeds
on unapproved work — at the cost of a batch pausing until the dispatcher says
merge.

`ry-couple.sh <id>` cuts the siding when the block lifts. It reads the base
branch as the clone sees it *then*, which is the whole point of waiting: cutting
at queue time would branch off a stale base and silently miss the work the task
depends on. It prefers the clone's own base branch when that is ahead of origin,
so a `local-only` blocker merged but never pushed is included, and refuses to
guess when the two have diverged.

`ry-deps.sh <id>` answers whether the blockers have cleared: `ready`, `pending`,
or `stranded`. Stranded means a blocker was decoupled without ever merging, so
the block can never lift on its own — the one case that needs a human. Decouple
records the status it archived as `outcome=` in the meta, without which
archiving would erase whether a blocker had merged.

The watcher couples every `ready` queued task on each pass, so a chain runs
itself down its length with no dispatcher in the loop. A stranded task is never
coupled; it becomes one inbox line and waits.

Edges only ever point at tasks that already exist, so the graph is a DAG by
construction and there is no cycle to detect.

## Authority rules (kept from firstmate)

- Yardmaster never edits projects; every change is an engine's job.
- Merge, discard, force-push, delete: explicit dispatcher word each time.
- Evidence is not authorization.
- No turn ends blind: the Stop hook on the yardmaster session checks for
  unread engine events before the turn can end.

## Build order

1. `ry-dispatch.sh` + `ry-decouple.sh` + worktree lib (bats-tested).
2. tmux lib + status-file contract + engine Stop hook.
3. `ry-watch.sh` daemon + yardmaster wake injection.
4. `ry-review-diff.sh`, `ry-merge-local.sh`.
5. `ry-pr.sh`, `ry-pr-poll.sh` (gh).
6. AGENTS.md + skills (`/manifest`, `/allaboard`, `/shed`, `/dispatch`).
7. Orca backend behind `RY_BACKEND`.
8. `no-mistakes` delivery mode.
9. Per-project base branches; the queue (`--after`, `ry-couple.sh`,
   `ry-deps.sh`, the watcher's promoter pass). Done.
