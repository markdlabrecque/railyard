# Railyard

*What railyard is, what each part of it does, and why each part is built the
way it is. For the dispatcher and for the agents that work here. How to use it
day to day is [`guide.md`](guide.md); the vocabulary is
[`CONTEXT.md`](../CONTEXT.md).*

Railyard is a personal agent distro: a folder of instructions, bash scripts and
state that turns Claude Code into a dispatcher running worker agents in git
worktrees. Built for one user. Inspired by firstmate (MIT); specific scripts
may be ported with attribution in the file header.

It is feature complete. Everything described below is built, tested and in use,
except the one item under [Future plans](#future-plans), which is named there
and refused everywhere else.

## The problem

Running several coding agents at once goes wrong in the same few ways. They
edit the same checkout and collide. Their work lands without anyone deciding it
should. You forget which one is waiting on you, and find out when you go
looking. And the supervision itself burns tokens — an agent polling for other
agents is an agent spending money to wait.

Railyard's answer to each, in order: one git worktree per task; every
irreversible act needs the dispatcher's word for that specific item; an inbox
that blocks the turn while a line is unread; and a supervisor that is a bash
loop, not a model.

## Scope

**In.** Claude Code as the only harness. tmux, Orca, cmux and herdr as
terminal backends, behind one seam. Plain `git worktree` for isolation. Two
task shapes and two delivery modes. An event-driven watcher that costs nothing
while idle. bats and shellcheck for tests.

**Out.** Other harnesses (codex, grok, pi, kimi, cursor, opencode). zellij and
other backends unless later wanted. Remote homes, chat relays, voice, AFK
digests.

**Names.** Script prefix `ry-`. Env prefix `RY_`. Home is the repo root
(`RY_HOME`). The vocabulary is railway operations, and it came from firstmate:

| firstmate | railyard | meaning |
| --- | --- | --- |
| captain | dispatcher | you |
| first mate | yardmaster | the main Claude Code session |
| crewmate | engine | one worker agent |
| spawn | dispatch | start a worker |
| worktree | siding | isolated checkout for one task |
| brief | waybill | task instructions handed to an engine |
| ship task | haul | task that changes and delivers code |
| scout task | survey | read-only investigation, report only |
| teardown | decouple | kill session, remove siding |
| bearings | manifest | queued and in-flight tasks (departures board) |
| stow | shed | end-of-session knowledge sweep |
| ahoy | allaboard | session recap and open decisions |

## Layout

```
railyard/
  AGENTS.md            always-loaded operating contract (short; routes to skills)
  CLAUDE.md            -> AGENTS.md
  bin/                 ry-*.sh scripts, one job each, *-lib.sh for shared code
  .claude/
    settings.json      hooks: SessionStart -> ry-session-start, Stop -> ry-turnend-guard
    skills/            /manifest /dispatch /allaboard /shed
  projects/            clones of your repos (gitignored)
  yard/                sidings: yard/<project>/<id>/ (gitignored)
  data/                durable: projects.md, yard.md, learnings.md, <id>/report.md
  state/               volatile: <id>.status <id>.meta inbox.md events.log (gitignored)
  tests/               bats
  docs/
```

---

# The features

## 1. One siding per task

Every change to a project is an engine's job, worked in its own git worktree
under `yard/<project>/<id>/` on branch `ry/<id>`. The yardmaster reads projects
and never edits them.

**Why a worktree and not a branch.** Two agents on one checkout collide on the
index, on the working tree, and on whatever the other one just checked out. A
worktree gives each engine a real directory it owns, while all of them share
one object store and one set of refs, so a merge is still just a merge.

**Why plain `git worktree`.** No treehouse, no wrapper, no bespoke isolation
layer. The projects railyard works on are ordinary clones, and a siding is an
ordinary worktree in them. If railyard vanished tomorrow, everything it left
behind would still be a git repository you can read.

## 2. Two task shapes

A **haul** changes a project and delivers the change. A **survey** is read-only:
it investigates, writes `data/<id>/report.md`, and never commits or pushes.
Shape is fixed at dispatch.

**Why the split is at dispatch and not in the waybill.** The constraint has to
be structural or it is not a constraint. A survey engine is told it is a survey
in its preamble, has no delivery path available to it, and produces a report as
its only artifact. Asking nicely in the prose for an agent not to commit is not
the same thing.

## 3. Delivery modes

How a finished haul reaches the base branch. Set per task at dispatch, or per
project in `data/projects.md`.

- **`local-only`** (default) — `bin/ry-merge-local.sh` fast-forwards the
  project's base branch onto `ry/<id>`. `--push` pushes it.
- **`pr`** — `bin/ry-pr.sh` pushes the branch and opens a PR on GitHub (`gh`)
  or an MR on GitLab (`glab`); `bin/ry-pr-poll.sh` watches the checks.

**Why fast-forward only.** `ry-merge-local.sh` refuses anything that is not a
clean fast-forward, and refuses a dirty siding or a dirty clone. A merge commit
made on your behalf, resolving conflicts nobody looked at, is exactly the class
of quiet mistake railyard exists to prevent. If the base moved, the siding
rebases first and you look at it again.

**Why the forge is detected, not configured.** `ry_forge()` reads the remote.
One less thing in `data/projects.md` to be wrong.

A third mode, `no-mistakes`, is named but refused. See
[Future plans](#future-plans).

## 4. Base branches

Sidings are cut from, and merged back into, a project's **base branch**.
Resolution order: `--base` on dispatch, then `base:` on the project's
`data/projects.md` line, then `develop` if the project has one, then the
remote's default branch.

**Why not just the default branch.** Railyard never touches the release branch.
Most of these projects release from `main` and integrate on `develop`, and an
agent landing work on the release branch is not a mistake you get to undo
quietly.

## 5. The core loop

1. You say what you want.
2. The yardmaster writes a waybill and runs `bin/ry-dispatch.sh`, which records
   `state/<id>.meta`, `.status` and `.waybill.md`, cuts the siding, and opens a
   terminal running Claude with the preamble and the waybill.
3. The engine works. Its Stop hook writes `state/<id>.status=turn-ended`,
   appends to `state/events.log`, and saves its final message to
   `state/<id>.last.md`.
4. `bin/ry-watch.sh` turns that event into one inbox line and nudges the
   yardmaster's terminal.
5. The yardmaster reviews (`bin/ry-review-diff.sh`), reports to you, and on
   your word delivers.
6. `bin/ry-decouple.sh` kills the terminal, removes the siding, archives the
   state.

**Why a status file and not a message queue.** The contract between an engine
and the yard is one file with one word in it, written by a hook the engine
cannot skip. Every backend writes it identically, every script reads it the
same way, and the whole supervision layer is a bash loop watching a directory.
Nothing to run, nothing to break, nothing to debug at 2am.

## 6. The watcher

`bin/ry-watch.sh` is a bash daemon polling `state/` every two seconds. Each
pass it couples queued tasks whose blockers have merged, turns new events into
inbox lines, polls open PRs, and flags engines that have gone quiet.

**Why polling, and why bash.** The yardmaster is the expensive thing. Any
design where a model waits for another model is a design that spends tokens to
sit still. A `sleep 2` loop reading `stat` costs nothing measurable and means
the yardmaster can end its turn the moment it has nothing to do — which is the
only reason "end your turn and wait" is safe advice.

**Why the nudge is not the record.** `state/inbox.md` is written first and the
terminal is nudged second. A nudge into a pane that has scrolled, or a session
that restarted, loses nothing: the line is still unread and the Stop hook will
say so.

## 7. The inbox, and the turn that cannot end blind

Unread engine events live in `state/inbox.md`. The yardmaster's Stop hook
(`bin/ry-turnend-guard.sh`) exits 2 while any line is unread, which blocks the
turn and prints the lines.

**Why block the turn rather than remind.** A reminder in context competes with
everything else in context. A hook that refuses to let the turn end is not a
suggestion. This is the single mechanism behind "nothing falls through the
cracks", and it is four lines of bash.

## 8. The queue

`--after <id>[,<id>...]` records blockers. The task is written to `state/` with
a waybill but no siding and no engine, and waits as `queued`.

**Why the block lifts on merge, not on the engine finishing.** A `DONE` verdict
is the engine's claim about its own work. The merge is the fact. Lifting on the
verdict would let a chain of tasks run itself down its whole length on work
nobody approved, which is the authority rules leaking. The cost is real — a
batch pauses until you say merge — and it is the right cost.

**Why the siding is cut late.** `bin/ry-couple.sh` reads the base branch as the
clone sees it *then*. Cutting at queue time would branch off a stale base and
silently miss the very work the task was waiting for. It prefers the clone's
own base branch when that is ahead of origin, so a `local-only` blocker merged
but never pushed is included, and it refuses to guess when the two have
diverged.

**Why stranded tasks are a decision, not a cleanup.** `bin/ry-deps.sh` answers
`ready`, `pending` or `stranded`. Stranded means a blocker was decoupled
without ever merging, so the block can never lift on its own. The watcher never
couples it and never drops it; it raises one inbox line and waits, because both
answers — drop the task, or re-dispatch it without that blocker — destroy
something.

Edges only point at tasks that already exist, so the graph is a DAG by
construction and there is no cycle to detect.

## 9. Holding the yard

Any Claude Code session started in this repo becomes the yardmaster. The
SessionStart hook then settles *which* session holds the yard, recording the
claim in `state/yardmaster.claim` as a pair: which backend, and which terminal
in it.

**Why a claim at all.** The identity is not the scarce thing — the inbox is.
Two yardmasters sharing one inbox take work from each other and neither is
told. A second session is told who holds the yard and stands down.

**Why one file rather than one per backend.** One file is what makes a yard
opened in two apps *visible*. When the claim names a backend other than this
session's, the session is told exactly that, instead of writing a second claim
the first would never see. It also means the watcher reads one place to find
the yardmaster, however many backends exist.

**Why there is a hand crank.** A claim goes stale on its own when its terminal
is gone. What the check cannot see is an agent that exited while its terminal
stayed open: the claim looks alive and every new session stands down forever.
`bin/ry-claim.sh` is for exactly that — `--show`, `--held`, `--json`,
`--release`, `--take`. Acting against a terminal that is still alive needs
`--force`, because being wrong costs two yardmasters on one inbox. `--held` is
the scriptable form: silent, exit 0 when a live terminal holds the yard, 1
otherwise, including when the claim names a terminal that has since closed.

## 10. More than one yard

A yard is a clone. `ry_home()` falls back to the repo containing `bin/`, so a
second clone is a second yard with its own `projects/`, `yard/`, `state/`,
watcher, claim and inbox.

**Why that is enough.** Nothing mutable is shared, so two yards cannot take
work from each other the way two sessions in one yard can. The one thing that
must be said out loud is `RY_TMUX_SESSION`, which `ry-yard.sh` passes into the
yardmaster it starts so that yardmaster's engines open in its own session.
Registering the same project in two yards is not prevented and is a bad idea:
two engines would work branches in one clone.

## 11. Backends

`bin/ry-backend-lib.sh` is the seam; nothing else in `bin/` branches on which
app is hosting terminals. A backend answers eight questions: open an engine
terminal, stop it, peek at it, send it text, nudge the yardmaster, name this
session's own terminal, name the claim file, and say whether a terminal is
still alive. There is a ninth it may decline, covered in §12.

An engine's backend and target are written into its meta when it launches, so
`ry-peek.sh`, `ry-send.sh` and `ry-decouple.sh` find the right terminal from
state alone. No env needed, and a yard survives `RY_BACKEND` changing under it
for engines already running.

**Which backend a yard uses.** `ry_backend()` reads `RY_BACKEND` if set, then a
`backend:` line in `data/yard.md`, then `tmux`. The file exists because a
yard's backend is a property of the yard, not of whatever shell you happen to
be in — the same reason `data/projects.md` records a project's mode and base.
Before it, getting the variable wrong produced a stood-down session rather than
a running yard. The environment still wins, deliberately: the test suite runs
on `RY_BACKEND=none` and overrides it per backend file, and a one-off run in
another app should not have to edit the yard. Errors name where the answer came
from, so a typo in a file you set months ago does not read as a typo in your
shell.

**tmux** is the reference. **Orca** hosts a terminal in our own siding
(`orca terminal create --worktree path:<siding>`) after the project clone is
registered as an Orca repo. **cmux** is the same shape with one workspace per
engine; two cmux facts drive the implementation — its printed handles are
positional refs that renumber when a workspace closes, so the target stored in
meta is always the stable uuid looked up by title, and its control socket only
accepts callers started inside cmux, which a cmux-hosted yard already is
because the watcher inherits `CMUX_SOCKET_PASSWORD`. **herdr** is one tab per
engine, and the only backend whose terminal needs two ids: the pane is what you
read and type into, the tab is what you close. Rather than teach the rest of
railyard about a second id, both travel in the one `target=` field as
`tab:<tab_id>/pane:<pane_id>`. Every herdr command answers in the socket API's
JSON envelope, so nothing is screen-scraped.

**Why a yard cannot split across apps.** An engine is welded to the backend
that launched it — peek, send and decouple only ever talk to that app — so a
yard with engines in two apps has engines it cannot reach the moment one app is
quit. `ry_backend_no_split()` refuses to open an engine beside engines in
another app. `bin/ry-dispatch.sh` and `bin/ry-couple.sh` both check before they
write anything, so a refused dispatch leaves no half-made task and a refused
couple leaves the siding uncut. `RY_ALLOW_SPLIT=1` overrides it for the case
the guard cannot judge: the other app is already gone and you want to carry on.

**Why viewers exist instead.** `bin/ry-view.sh <herdr|orca|cmux>` opens one
terminal in that app running `tmux new-session -t railyard -s railyard-<app>`.
The yard stays in tmux and the other apps are viewports onto it, so no engine
is ever welded to an app you might quit. Viewer sessions join the yard's
session group, so two viewers do not fight over window size or which window is
current, and they clean themselves up on detach. A second viewer on the same
app takes `railyard-herdr-2` rather than stealing the first one's client.

The cost is the one we accepted going in: the viewing app sees `tmux` in that
terminal rather than `claude`, so its native agent detection stays dark. It
does not matter, because railyard's status comes from the Stop hook and the
inbox, not from what an app infers about a process.

**What this replaced.** Moving a running engine between backends — stopping it
and relaunching with `claude --resume` elsewhere — was considered and not
built. It is lossy, and viewers remove the reason to want it.

## 12. Knowing an engine has stopped

An engine that ends a turn writes its status file. An engine that stops
*without* ending a turn — sitting at a prompt, waiting on something — writes
nothing, and the watcher notices after `RY_STALL_MIN` minutes of silence
(default 20) with one inbox line.

herdr watches the agent in each pane, so it knows this within seconds.
`ry_backend_blocked()` is the ninth backend question, and the only one a
backend may decline to answer.

**Why it is narrow on purpose.** The tempting version was to let herdr report
turn ends directly. That would give one backend its own path into the status
file, and the contract's whole value is that every backend writes it the same
way. So the question is not "has this engine finished" — that stays the Stop
hook's to answer — but "is this engine sitting at a prompt right now". The
answer changes no state and adds no event kind. Its only effect is that an
existing inbox line is raised in seconds instead of minutes. Backends that
cannot tell return false and the timer does the work, exactly as before.

**Why anything unexpected means "cannot tell".** An old herdr, a pane it does
not treat as an agent, a socket error — all read as not-blocked, never as
blocked. A false blocked wakes the dispatcher about an engine that is working,
which is the failure that would make the feature not worth having.

## 13. Authority rules

Kept from firstmate, and the reason most of the above is shaped as it is.

- The yardmaster never edits projects; every change is an engine's job.
- Merge, discard, force-push, delete: the dispatcher's explicit word each time,
  given for that specific item.
- Evidence is not authorization. A green test run is not a merge approval.
- No turn ends blind.

## 14. Tests

bats plus shellcheck, run against fake CLIs on `PATH` (`tests/fakebin/`) so CI
needs none of the real apps — no Orca, no cmux, no herdr, and a private tmux
socket that never touches yours.

**Why fakes rather than mocks or integration tests.** Each backend is a thin
shell over somebody else's CLI. What can break is the arguments we pass and the
JSON we parse, and a fake CLI that logs its argv tests exactly that. The real
apps are tested by using them.

---

# What shipped, in order

1. `ry-dispatch.sh`, `ry-decouple.sh`, worktree lib.
2. tmux lib, the status-file contract, the engine Stop hook.
3. `ry-watch.sh` and yardmaster wake injection.
4. `ry-review-diff.sh`, `ry-merge-local.sh`.
5. `ry-pr.sh`, `ry-pr-poll.sh`.
6. `AGENTS.md` and the skills (`/manifest`, `/dispatch`, `/allaboard`, `/shed`).
7. Orca behind `RY_BACKEND`.
8. Per-project base branches; the queue (`--after`, `ry-couple.sh`,
   `ry-deps.sh`, the watcher's coupling pass).
9. cmux and herdr; one claim file replacing the per-backend ones.
10. `ry-view.sh` viewers; the split-yard guard; `ry-claim.sh --held`.
11. The yard's recorded backend; `ry_backend_blocked()`.

The `no-mistakes` delivery mode was item 8 in the original build order and is
the one thing still open. It moved to Future plans rather than being built,
because it depends on a tool that is not installed here.

---

# Future plans

Nothing below blocks anything. Railyard works without all of it.

## `no-mistakes` delivery mode

**What it is.** [no-mistakes](https://github.com/kunchenguid/no-mistakes) is a
git proxy that gates pushes. `no-mistakes init` adds a git remote of that name
pointing at a bare gate repo under `~/.no-mistakes/repos/`. You
`git push no-mistakes <branch>` instead of `origin`; it runs a validation
pipeline in a disposable worktree, auto-fixes what it safely can, escalates
judgment calls to a human, and forwards the branch and opens the PR only once
every check is green.

**Why it was reserved.** `no-mistakes` was in railyard's mode list from the
first commit, marked "reserved; wired when installed". It was never defined
here because it was never meant to be defined here — it is somebody else's
tool, and the mode is just the instruction to deliver through it.

**Why dispatch refuses it today.** `bin/ry-dispatch.sh` accepted the mode and
wrote it into the task's meta, while `ry-merge-local.sh` takes only
`local-only` and `ry-pr.sh` only `pr`. A `no-mistakes` haul could be
dispatched, run, finish, and then have no way to be delivered. A mode that can
be chosen and not honoured is worse than one that does not exist, so it is
refused with a message naming the modes that work.

**What wiring it would take.** Less than it looks.

- Delivery is `ry-pr.sh` with two lines changed: push to the `no-mistakes`
  remote rather than `origin`, and let the tool open the PR rather than calling
  `gh`/`glab`.
- The push is asynchronous. It answers "pipeline started" with no PR URL, so
  the watcher needs a poll step — the tool ships `no-mistakes axi`, a
  non-interactive interface, for this — that waits for the run, picks up the
  PR URL, and hands off to the existing `ry-pr-poll.sh` path.
- The mode has to be refused at *dispatch* when the project clone has no
  `no-mistakes` remote, not discovered at delivery. Which is the bug that got
  the mode dropped in the first place.

**Why it is per-project.** The tool installs once per machine (a binary in
`~/.no-mistakes/bin`, and its `/no-mistakes` skill at user level) but is
initialised once per repo, and its pipeline is configured by a
`.no-mistakes.yaml` committed at the repo root. What "verified" means is not
the same for a Drupal site and a bash tool, so the rules live with the code and
travel with it. That fits railyard's existing shape: the mode belongs on the
project's `data/projects.md` line, beside `base:`.

**Not installed here.** No binary on `PATH`, no `~/.no-mistakes`, no
`/no-mistakes` skill, and no project under `projects/` has the remote. Build it
when that changes.

## Orca's mobile view

Whether Orca's mobile view mirrors an arbitrary command terminal, or only ones
it started itself. The `orca` viewer in `ry-view.sh` is implemented the same
way as the other two. If the mobile view turns out not to mirror it, that is a
limitation of the viewer, not of the command. Left to try rather than to
design.

## Backends and harnesses not taken

zellij. Other harnesses (codex, grok, pi, kimi, cursor, opencode) — the
status-file contract is harness-shaped, not model-shaped, so another harness
means another Stop hook and nothing more, but nothing needs it yet.
