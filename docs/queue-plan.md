# Build plan: base branches and the queue

Goal: batch a set of tickets, declare which ones are blocked behind which, and
have railyard launch each one by itself once its blockers are merged into
`develop`.

Two independent things, built in order. Piece 1 is useful on its own and ships
first.

## Ground rules this plan assumes

- Feature work branches off `develop` and merges back into `develop`.
- Railyard never touches `main`. Releases are cut outside railyard and are not
  represented in it at all.
- A block lifts when the blocker is **merged**, not when its engine finishes.
  A `DONE` verdict is a claim; the merge is the fact.

## Piece 1 — base branch is configurable

Today `ry_default_branch` (`bin/ry-lib.sh:22`) reads `origin/HEAD` and every
script takes that as gospel. `develop` cannot be expressed.

The good news: `state/<id>.meta` already carries `base=`, and both
`ry-merge-local.sh:31` and `ry-pr.sh:39` already read it. **Only dispatch needs
to change.**

**Changes**

- `data/projects.md` line format gains an optional field:
  `` - `proj` — pr, base: develop, notes: ... ``
- New `ry_project_base <project>` in `ry-lib.sh`: read that line, extract
  `base: <branch>`, fall back to `ry_default_branch`.
- `ry-dispatch.sh` gains `--base <branch>` to override per task.
- Validate before creating anything: `git rev-parse --verify origin/<base>`,
  die with a clear message if it does not exist.

**Tests** — dispatch honors `projects.md`; honors `--base`; falls back to
`origin/HEAD` when neither is set; dies on an unknown branch.

## Piece 2 — a task can be queued instead of launched

Today `ry-dispatch.sh` creates the worktree and calls `ry-engine-launch.sh` in
one breath. Nothing can wait.

**Split it.**

- `bin/ry-couple.sh <id>` — new. Takes a `queued` task, fetches, creates the
  siding, sets status `dispatched`, launches the engine. This is the second
  half of today's dispatch, extracted verbatim.
- `ry-dispatch.sh` with no `--after` writes meta + waybill, then calls
  `ry-couple.sh`. Behavior for existing use is unchanged.
- `ry-dispatch.sh --after <id>[,<id>]` writes meta with `after=`, sets status
  `queued`, and **stops**. No worktree, no engine.

**Why no worktree at queue time.** The siding must branch off `develop` *as it
is when the blocker has landed*. Cutting it at queue time would branch off
stale `develop` and silently miss the work it depends on. The meta records the
intended `siding=` path; the directory appears at coupling.

**Which ref to branch from.** `ry-couple.sh` must fast-forward the local
`<base>` from `origin/<base>` and branch off the **local** ref, not
`origin/<base>`. A `local-only` blocker merged without `--push` exists only in
the project clone; branching off the remote ref would lose it. Today's dispatch
uses `origin/<base>` and is correct only because nothing can depend on anything.

**Tests** — `--after` creates no worktree and no tmux window; couple creates
the siding at the right commit; couple on a non-queued id refuses; a
locally-merged, unpushed blocker is present in the coupled siding.

## Piece 3 — dependency edges

- `after=<id>[,<id>...]` in `state/<id>.meta`.
- Validate at dispatch: every id must have a meta file (live or archived).
- Refuse cycles: walk the `after` graph before writing the edge.
- New `ry_status_of <id>` in `ry-lib.sh`: read `state/<id>.status`, falling back
  to `state/archive/<id>/<id>.status`. Without this, decoupling a blocker
  orphans everything queued behind it.

**Stranded tasks.** If a blocker is archived having never reached `merged` —
dropped, or its MR closed — nothing behind it can ever unblock. Do not silently
launch and do not silently rot. Emit one `blocked-stranded` event so it becomes
an inbox line, and let the dispatcher drop it or release the block by hand.
This is the one case that needs a human.

**Tests** — cycle is refused; unknown blocker id is refused; status resolves
through the archive; a dropped blocker strands its dependents exactly once.

## Piece 4 — the promoter

A fourth pass in `ry-watch.sh`, alongside events, stalls and PR polling.

For each task with status `queued`:

- every blocker `merged` → run `ry-couple.sh <id>`, append a `launched` event
- any blocker stranded → append `blocked-stranded` once, guarded by a marker
  file the way `.checks-failed` already is
- otherwise → leave it alone

The merge signal already exists on both paths: `ry-merge-local.sh:32` and
`ry-pr-poll.sh:41` both set status `merged`. Nothing new to detect.

**Tests** — a queued task with a merged blocker gets coupled once, not twice; a
queued task with a pending blocker is left alone; a stranded task warns once.

## Piece 5 — the manifest shows the queue

`ry-manifest.sh` currently loops `running turn-ended pr-open merged dispatched
blocked`. Nothing ever writes `blocked` — it is a verdict, not a status, and
that branch is dead.

- Add `queued` at the top of the loop.
- Drop the dead `blocked` branch.
- Queued rows show `after <ids>` and flag stranded ones.

## Piece 6 — words and docs

- `CONTEXT.md`: add **Queued**, **Couple**, **Blocker**, **Stranded**, and
  **Base branch**. Extend the **Status** entry with `queued`.
- `docs/design.md`: vocabulary table and build order.
- `AGENTS.md`: intake decides dependencies alongside shape, project and mode.
- `/dispatch` skill: teach `--after` and per-project base.

## Order of work

Piece 1 alone, shipped and green — it is independently useful and unblocks
nothing else.

Then the tracer bullet through pieces 2–4 at their thinnest: dispatch A, queue
B after A, merge A, watch B couple and run on its own. One real end-to-end
pass before any polish. Pieces 5 and 6 follow.

Each piece lands on its own feature branch off `develop` with bats coverage.
