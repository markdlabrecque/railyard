# Railyard: a guide for the dispatcher

*For the human. Agents get their instructions from [`../AGENTS.md`](../AGENTS.md)
and do not need this file.*

Railyard runs Claude Code agents on your repos, one isolated git worktree per
task, and keeps you in the loop for every decision that matters. You are the
**dispatcher**. The session you talk to is the **yardmaster**. It reads your
projects and never edits them — every change is an **engine's** job.

Vocabulary is in [`../CONTEXT.md`](../CONTEXT.md); why it works this way is in
[`prd.md`](prd.md). This is how to use it.

## First run

A fresh clone carries no configuration. Both files that configure a yard —
`data/yard.md` (the backend) and `data/projects.md` (the registered projects) —
are machine-local and gitignored, so they do not travel with the repo. Until
you write them, this is a tmux yard with no projects, and the first yardmaster
session says so instead of leaving you to find out. Create them by hand:

```sh
mkdir -p data
echo '- `backend: tmux`' > data/yard.md     # or orca, cmux, herdr
git clone <url> projects/myapp
echo '- `myapp` — local-only, notes: main repo' > data/projects.md
```

[Choosing this yard's backend](#choosing-this-yards-backend) and
[Register a project](#register-a-project) cover the fields. Once either file
exists the notice stops: a yard with no `data/yard.md` and a project list is a
tmux yard on purpose.

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

## Choosing this yard's backend

tmux is the default; Orca, cmux and herdr are the other supported
**backends** — the thing that hosts terminals. Rather than remember
`RY_BACKEND` in every shell, record it once in `data/yard.md`:

```
- `backend: herdr`
```

`data/yard.md` is yours alone: it is gitignored, it is not in the repo, and it
does not arrive with a clone — create it yourself on each machine you run a
yard on. It holds live yard state, and tracking it puts that state at the
mercy of git: any operation that updates the file's path — a checkout, a
merge, a hard reset — can put an older copy back. That happened here,
silently, with an engine running.

`bin/ry-yard.sh` then opens the yard there, and carries the choice into the
yardmaster, so every engine it dispatches lands in the same app. `RY_BACKEND`
in the environment still wins, so a one-off override works as before; with
neither, the yard is a tmux yard.

A yard runs on **one** backend at a time. An engine can only be reached
through the app that launched it, so railyard refuses to open an engine beside
engines in another app (`RY_ALLOW_SPLIT=1` overrides). To see a tmux yard from
somewhere else, use `bin/ry-view.sh` — see below — rather than changing the
line.

## Running in Orca

Orca, cmux and herdr each host a whole yard. Railyard still owns everything
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
error: this yard already has engines on herdr (16-name-work-by-ticket), and tmux
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
- **herdr notices a stuck engine faster.** It watches the agent in each pane,
  so when an engine stops without ending its turn the watcher raises it in
  seconds rather than after `RY_STALL_MIN` minutes. Same inbox line, same once
  per engine; on the other backends the timer still does the work.

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

Then add a line to `data/projects.md`, creating the file if it is not there:

```text
- `myapp` — pr, base: develop, notes: main repo
```

Like `data/yard.md`, `data/projects.md` is machine-local: gitignored, not in
the repo, and absent from a fresh clone. It holds live yard state, and a
tracked file can be put back to an older copy by any git operation that
updates its path — a checkout, a merge, a hard reset. It also lists the
clones under `projects/`, which are this machine's — another machine's yard
registers its own.

`name` must match the directory under `projects/`. Both other fields are
optional:

- **mode** — how finished hauls are delivered: `local-only` or `pr`.
  Defaults to `local-only`.
- **base** — the branch sidings are cut from and merged back into. Defaults to
  `develop` when the project has one, otherwise the remote's default branch.
  Railyard never touches your release branch.

## Fixtures

`fixtures/` at the railyard root holds the machine-local files a project's
siding needs to start from — a database dump being the obvious case. One
directory per project:

```
fixtures/
  myapp/
    db.sql.gz
```

It is gitignored, like `projects/`, `yard/`, `state/` and `data/<id>/`, because
these files are large, machine-local, and often contain client data. Nothing in
railyard reads them; they exist for the project's own start script.

Railyard creates `fixtures/<project>/` when it couples a siding, so a start
script can rely on the directory existing and simply find it empty. Drop the
files in yourself; nothing else does.

## The worktree start script

A fresh siding is a bare git worktree. For a project that needs a database or a
warmed-up environment before anything can be verified, that is not enough — and
an engine should never have to improvise it, nor a waybill carry environment
instructions that have nothing to do with the task.

So a project may set up its own sidings. Put an executable script here, inside
the project repo, where it is versioned alongside the code it sets up:

```
.railyard/worktree-start.sh
```

That is the whole declaration: railyard looks at that one path, and does
nothing at all when it is absent. No config line, no registration.

### The contract

| | |
|---|---|
| **Path** | `.railyard/worktree-start.sh` in the project repo. Found by path or not at all. |
| **When** | At couple time: after the siding is cut and after its `.ddev/config.local.yaml` name override is written, before the engine launches. So `ddev` is safe to call. |
| **Shape** | Runs for every task, hauls and surveys alike. |
| **Interpreter** | `bash`, unless the file is executable *and* starts with a `#!` line — then that shebang is honoured, so a start script may be Python or anything else. Never `/bin/sh`: it is bash on macOS and dash on Debian and Ubuntu, so a script that relied on it would work on one machine and not the other. Give a non-bash script both a shebang and the execute bit; without them it runs under bash. |
| **Working directory** | The siding. |
| **Output** | stdout and stderr, captured to `state/<id>.start.log`. That log is the record of what setup did; nothing streams anywhere else. |
| **Timeout** | 600 seconds, then the script and its children are killed. |
| **Failure** | Never blocks the dispatch. |
| **Trust** | None needed. It is the project's own script. |

### Environment

| Variable | |
|---|---|
| `RY_FIXTURE_PATH` | **`fixtures/<project>/` — the project's own directory, not the `fixtures/` root.** A start script never has to know its project's directory name; read this and look inside. Railyard creates it if it is missing, so it always exists and may be empty. |
| `RY_SIDING` | The siding's path. Same as `$PWD`. |
| `RY_PROJECT` | The project name, as it appears under `projects/`. |
| `RY_ID` | The task id. Useful for a per-siding resource name. |
| `RY_HOME` | The railyard root. |
| `RY_BIN` | Railyard's `bin/`. |
| `RY_BACKEND` | Where the engine's terminal will live. |

A DDEV project's name is already set for you, in the siding's gitignored
`.ddev/config.local.yaml`, so `ddev start` in the script gets this siding's own
project rather than colliding with another one. Read the name from there if the
script needs it; do not invent one.

Everything else is the script's own business. Railyard does not care what it
does, only whether it exited.

### When it fails

A failing start script does not abort the dispatch. Three things happen and
then the engine launches anyway:

1. The exit status and the log path become an inbox line, so the yardmaster
   sees it without polling:
   `[railyard] engine <id> start-script-failed: exit 3; output in state/<id>.start.log`
2. The engine is told, in its own prompt, that setup failed and why — and told
   plainly that repairing the script is not its job. It carries on if the task
   does not need the environment (a read-only survey usually does not) and
   reports `BLOCKED` if it does. It never fabricates a result it could not
   verify.
3. `ry-couple.sh` says so on stderr, so a dispatch never quietly opens onto a
   broken environment.

Nobody reruns the script by hand. The engine is still working in that siding,
so a rerun would move the worktree and the database under it while the engine
still holds the original "setup failed" notice. Fixing a project's setup is a
change to a project, which means a new engine on a fresh siding — after the
affected one has been stopped or decoupled.

A script that hangs is worse than one that fails: it would hold the dispatch
open with no engine and no inbox line. So it is killed after **600 seconds**,
along with anything it started, and reported as a timeout rather than an exit
status — the two mean different things to whoever debugs it:

```
[railyard] engine <id> start-script-failed: timeout 600s; output in state/<id>.start.log
```

`RY_START_TIMEOUT` overrides the bound, in seconds. It must be a whole number
of at least 1; anything else (a typo, a unit suffix) is refused out loud on
stderr and the 600-second default is used instead, because an unusable bound
would leave the watchdog never firing — exactly the hang it exists to prevent.
It exists so the test suite does not sit for ten minutes; there is no reason to
set it by hand.

## The daily loop

**Ask for work.** Plain language is enough. `/dispatch myapp fix the flaky
login test` dispatches one engine; describing several tasks dispatches several.

The yardmaster decides two things per task and tells you what it picked:

- **shape** — `haul` changes code and ships it; `survey` is read-only and
  writes a report to `data/<id>/report.md`.
- **mode** — from the project's registered mode. Say "use local-only for this
  one" to override.

**Naming.** A task is named after the work, not after railyard. With a ticket
the id is `<number>-<slug>` — `3-fixtures-start-script`; without one it is the
slug alone — `news-filter-styling`. That id is the siding directory, the branch
(`ry/<id>`) and every `state/<id>.*` file. Two tasks on one ticket is normal, so
the second gets `-2`. The yardmaster picks the slug; you can name it yourself in
the ask, and ids made before this scheme keep working.

In what the yardmaster says back to you, a ticket is `#N` and a pull or merge
request is `!N` — the same on GitHub and GitLab, so the two never blur. Task
ids, branch names and commit hashes are mechanics: they come after the outcome,
if at all.

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
  #12  12-news-filter-styling  myapp  haul  pr  4m
      waiting on 11-news-filter-query
RUNNING
  #11  11-news-filter-query  myapp  haul  pr  9m
inbox: 0 unread
```

The **inbox** is engine events you have not acted on yet. The yardmaster's turn
is blocked while any line is unread — deliberately. Nothing falls through.

Two more session commands:

- `/allaboard` — recap of the session and any open decisions.
- `/shed` — end-of-session sweep; durable lessons land in `data/learnings.md`.

`data/learnings.md` is a queue, not an archive. `/shed` files into it; session
start, `/manifest` and `/allaboard` empty it. Each line is promoted somewhere
that enforces it — the engine preamble, `AGENTS.md`, a project's line in
`data/projects.md`, a check in a script — or dropped. Promotions need your word,
so you see the whole queue before anything goes. Nothing accumulates, and
nothing is carried forward undecided.

## When something goes wrong

**`engine <id> silent for Nm`** — a running engine ended no turn. Look at it:
`bin/ry-peek.sh <id>`.

**`engine <id> waiting for input`** — the same thing, spotted at once instead
of waited out: the backend says that engine's agent is sitting at a prompt.
Only herdr can tell railyard this today. Same response: `bin/ry-peek.sh <id>`.

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
| `bin/ry-dispatch.sh --haul\|--survey [--mode <m>] [--base <b>] [--after <id>] [--ticket <n>] [--slug <text>] <project> "<waybill>"` | dispatch or queue a task |
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
