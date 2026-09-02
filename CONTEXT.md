# Railyard

*For the dispatcher and every agent.*

A personal agent distro: instructions, bash scripts, and state that turn Claude Code
into a dispatcher running worker agents in git worktrees. The vocabulary is drawn
from railway operations — every term below has one meaning and one spelling.

## Language

### People and agents

**Dispatcher**:
The human. The only authority for merging, pushing, discarding work, and
decoupling a siding that holds uncommitted work.
_Avoid_: captain, user, operator

**Yardmaster**:
The main Claude Code session. Reads projects, dispatches engines, reviews their
work, and reports to the dispatcher. Never edits a project itself. One session
holds the yard at a time; a second one stands down rather than share the inbox.
_Avoid_: first mate, orchestrator, main agent, supervisor

**Engine**:
One worker agent, running in its own siding, working one task to a handoff.
_Avoid_: crewmate, worker, subagent, child

**Inspector**:
A read-only agent an engine spawns inside its own siding to review the work
before it hands off. Fresh context: it sees the artifacts, never the engine's
reasoning. It is not the yardmaster's `bin/ry-review-diff.sh`, and it holds no
authority — it raises findings, the engine answers them.
_Avoid_: reviewer, checker, QA

### Work

**Task**:
One unit of dispatched work. Has exactly one shape, one project, one engine, one
siding, and one id.

**Id**:
A task's name, and the one the dispatcher uses: `<ticket>-<slug>` when the work
has a ticket (`3-fixtures-start-script`), the slug alone when it does not
(`news-filter-styling`). A second task of the same name gets `-2`. It is the
siding directory, the branch `ry/<id>`, and every `state/<id>.*` file.
_Avoid_: task name, slug

**Shape**:
Whether a task changes code or only reads it — `haul` or `survey`. Fixed at dispatch.
_Avoid_: kind, type

**Haul**:
A task that changes a project and delivers the change.
_Avoid_: ship task, feature, change task

**Survey**:
A read-only investigation that produces a report and never commits or pushes.
_Avoid_: scout task, research task, spike, investigation

**Mode**:
How a completed haul is delivered — `local-only` or `pr`. Applies
to hauls only; a survey has no mode. Distinct from **Shape**.
_Avoid_: delivery method, strategy

**Waybill**:
The task instructions handed to an engine: goal, acceptance criteria, constraints,
areas to look at, and what "verified" means. Written by the yardmaster. Its first
line is the task's **title**, not prose — see AGENTS.md § Waybill.
_Avoid_: brief, prompt, ticket, spec

**Report**:
A survey's output, written to `data/<id>/report.md`. A haul produces commits, not
a report.

### Places

**Project**:
A clone of one of the dispatcher's repositories, living under `projects/`. Read by
the yardmaster, never written by it.
_Avoid_: repo, codebase

**Siding**:
The isolated git worktree for one task, on branch `ry/<id>`. Created at dispatch,
removed at decouple.
_Avoid_: worktree, workspace, branch, checkout

**Base branch**:
The branch a project's sidings are cut from and merged back into — `develop` by
default. Resolved from `--base`, then the project's `data/projects.md` line, then
`develop` if the project has one, then the remote's default branch. Railyard
never touches the release branch; releases are cut outside it.
_Avoid_: default branch, target branch, trunk, main

**Fixtures**:
The machine-local files a project's siding starts from — a database dump, say —
kept per project under `fixtures/<project>/` and gitignored. Read by the
project's own start script, never by railyard.
_Avoid_: seeds, test data, dumps

**Start script**:
A project's own `.railyard/worktree-start.sh`, run in a freshly cut siding
before its engine launches, so the engine opens onto a working environment. Its
contract is in `docs/guide.md`.
_Avoid_: bootstrap, provisioning, setup hook

**Yard**:
The whole railyard installation, and the terminals it runs in — a tmux session named `railyard` by default, or Orca terminals / cmux workspaces / herdr tabs when `data/yard.md` or `RY_BACKEND` says so.

### Actions

**Dispatch**:
To create a siding and start an engine on a waybill.
_Avoid_: spawn, launch, kick off, assign

**Review**:
The yardmaster's judgement of a finished engine's work against its waybill, before
anything is delivered. Correctness has already been inspected in the siding; what
review adds is waybill fit, which only the yardmaster can judge.

**Inspection**:
The block an engine's handoff carries on a haul, recording the inspector's
verdict, the suite result, the must-fix findings, the revert check and the risk.
`bin/ry-verdict.sh <id>` prints it and fails when it is missing or malformed.
_Avoid_: verdict block, review block, QA report

**Revert check**:
One assertion, named by file and line, that fails when the change is reverted —
run on a reverted copy and watched to fail. The one claim in a handoff that is
checkable from outside the siding.
_Avoid_: mutation test, sanity check

**Couple**:
To cut a task's siding and start its engine. Separate from dispatch because a
queued task is coupled only once its blockers have landed, so its siding is cut
from a base that already contains their work.
_Avoid_: launch, start, spawn

**Decouple**:
To kill an engine's window, remove its siding, and archive its state. The end of a
task's life, whatever its outcome.
_Avoid_: teardown, cleanup, close, finish

**Shed**:
The end-of-session knowledge sweep that appends durable lessons to `data/learnings.md`.
_Avoid_: stow, retro, wrap-up

**Promote**:
To move a filed learning out of `data/learnings.md` and into something that
enforces it — the engine preamble, `AGENTS.md`, a project's `data/projects.md`
line, or a check in a script. The only way a learning survives its queue; every
line not promoted in that pass is dropped. Needs the dispatcher's word.
_Avoid_: file, keep, save, adopt

**Allaboard**:
The session recap: what happened, and which decisions are still open.
_Avoid_: ahoy, summary, standup

### Status and outcome

A task's **status** and an engine's **verdict** are different things and must not be
used interchangeably.

**Status**:
Where a task is in its lifecycle, held in `state/<id>.status`. One of:
`queued` → `dispatched` → `running` → `turn-ended` → `merged` | `pr-open` →
`decoupled`. Written only by the scripts.

**Queued**:
The status of a task that has a waybill but no siding and no engine, because it
is waiting on its blockers. Coupling is what ends it.
_Avoid_: pending, waiting, backlogged, blocked

**Blocker**:
A task that another task waits on, recorded as `after=<id>` in the waiting
task's meta. The block lifts when the blocker is merged into the base branch.
_Avoid_: dependency, parent, upstream

**Turn-ended**:
The status meaning an engine finished a turn and is now awaiting review. It says
nothing about whether the work succeeded.
_Avoid_: done, finished, complete — those describe the verdict, not the status

**Verdict**:
The engine's own judgement of its work, the first word of its final message:
`DONE:` or `BLOCKED:`. A `DONE` verdict is a claim, not an approval — the review
decides.
_Avoid_: result, outcome, exit status

**Blocked**:
A verdict meaning the engine hit a question its waybill does not answer. The
question becomes the yardmaster's decision, or the dispatcher's.

### Awareness

**Event**:
One append-only line in `state/events.log` recording something that happened to a
task: `turn-ended`, `pr-merged`, `pr-checks-failed`. The permanent record.

**Inbox**:
The unread events awaiting the yardmaster's action, in `state/inbox.md`. A line is
unread until the yardmaster has acted on it and acknowledged it. The Stop hook
blocks the yardmaster's turn while any line is unread.
_Avoid_: queue, notifications, backlog

**Manifest**:
The at-a-glance digest of every task not yet decoupled — queued and in flight — a
departures board. Derived from task state, not stored.
_Avoid_: board, bearings, backlog, dashboard, status page

**Watcher**:
The background daemon that couples queued tasks whose blockers have merged,
turns events into inbox lines, wakes the yardmaster, polls open PRs, and flags
engines that have gone silent.
_Avoid_: monitor, poller, daemon

**Stranded**:
A queued task whose blocker was decoupled without ever merging, so its block can
never lift on its own. Always a decision for the dispatcher: drop the task, or
release the block by hand.
_Avoid_: orphaned, dead, abandoned

**Outcome**:
The status a task held when it was decoupled, kept in its archived meta. Without
it, archiving would erase whether a blocker ever merged.

**Stall**:
A task whose status is still `running` after too long with no turn end. Reported
once, and never a status of its own.
