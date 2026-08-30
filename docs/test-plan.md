# Railyard first real run — test plan

*For the dispatcher — a manual script for proving the loop on a real project.*

Goal: prove the loop on one of your real GitLab projects, low risk, in about 30 minutes. Every step says what to do, what you should see, and what to note if it differs.

Pick a project that: lives on your self-hosted GitLab, has a test suite the engine can run, and where a throwaway branch/MR is harmless. Call it `<proj>` below.

## 0. Setup (once)

```sh
cd ~/Projects/railyard
git clone <gitlab-ssh-url> projects/<proj>
echo '- `<proj>` — pr, notes: first real run' >> data/projects.md
bats tests            # expect 106 ok
glab auth status      # expect: logged in to your GitLab host
```

## 1. Open the yard

```sh
bin/ry-yard.sh
```
See: a tmux session `railyard`, window `yard`, Claude starting in this repo. The SessionStart hook silently adds `railyard: 0 engine(s) running, 0 turn-ended, 0 unread inbox line(s)` to Claude's context; you will not see it printed.
Check it ran, either way: ask the yard `what did the railyard session start hook report?` (Claude quotes the line), or from another terminal `cat state/yardmaster.pane` shows a `%N` and `cat state/.watch.lock` shows a live pid (`kill -0 <pid>`).
Note if: no summary line (hook did not run) or no pane file (Claude was started outside tmux).
On Orca: `RY_BACKEND=orca bin/ry-yard.sh` instead — an Orca terminal titled `yardmaster`, and the claim lands in `state/yardmaster.orca`. Everywhere below that says a tmux window `ry-<id>`, read an Orca terminal `ry-<id>`; use `bin/ry-peek.sh <id>` rather than `tmux capture-pane`.

## 2. Manifest, empty

In the yard: `/manifest`
See: `no engines`, `inbox: 0 unread`.

## 3. Survey (read-only, no risk)

In the yard: `/dispatch <proj> investigate how tests are run in this project and list the exact commands, plus anything flaky or slow you can tell from CI config`
See: one reply line: `Dispatched: survey, none, id <proj>-MMDD-HHMM-xxxx`.
Then: `tmux select-window -t railyard:ry-<id>` (or `Ctrl-b n`) to watch the engine. It should start without a trust dialog and work read-only.
Within ~2–5 min the yard window receives `[railyard] engine <id> turn-ended: DONE: ...`. The yardmaster reads `data/<id>/report.md`, relays findings, acks the inbox.
Check: `bin/ry-manifest.sh` shows the engine under TURN-ENDED; `git -C projects/<proj> status` is clean (engine changed nothing).
Then in the yard: `decouple <id>` → siding gone, `state/archive/<id>/` exists.
Note if: trust dialog appeared; wake line never arrived (check `state/inbox.md` and `state/watch.log`); the yardmaster edited anything itself.

## 4. Haul, local-only (change, no push)

In the yard: `/dispatch <proj> <a small, real, self-contained change with a clear test — e.g. fix a typo in a user-visible string and update its test>`
Ask for mode local-only if `/dispatch` picks pr: `use local-only for this one`.
See: dispatched line; engine works in `yard/<proj>/<id>/`; wake line with `DONE:`; yardmaster runs `bin/ry-review-diff.sh <id>`, summarizes, and asks: merge?
Reply: `merge it`.
Check: `git -C projects/<proj> log --oneline -3` has the engine's commit on the default branch; `git -C projects/<proj> status -sb` shows `ahead 1` (not pushed). `state/<id>.status` = `merged`.
Reset for the next step (this run is a test): `git -C projects/<proj> reset --hard origin/<default>` and `decouple --delete-branch <id>` in the yard.
Note if: the yardmaster merged without asking; review output missed the commits; the engine left uncommitted work (review prints `WARNING: UNCOMMITTED`).

## 5. Haul, pr mode (the GitLab path — the one piece never run for real)

In the yard: `/dispatch <proj> <another tiny change> — mode pr`
After the `DONE:` wake and review, reply: `open the MR`.
See: yardmaster runs `bin/ry-pr.sh <id>`; reply contains the full MR URL on your GitLab host; `state/<id>.status` = `pr-open`; `grep pr_url state/<id>.meta`.
Open the URL in Firefox: source branch `ry/<id>`, target = default branch, title = commit subject, description = waybill + commit list.
Wait for CI. The watcher polls every 2 min. If CI fails: within ~2 min the yard gets `[railyard] engine <id> pr-checks-failed: <url>`.
Merge the MR in GitLab (or let it fail and close it). Within ~2 min: `[railyard] engine <id> pr-merged: <url>`; yardmaster reports it and proposes decouple.
Reply: `decouple it`.
Note if: `glab mr create` errored (paste the error — likely a flag or auth difference on your glab version); URL parse failed; no pr-merged wake (run `bin/ry-pr-poll.sh <id>` by hand and paste the output).

## 6. Session hygiene

In the yard: `/allaboard` → recap of steps 3–5 and no open decisions.
Then: `/shed` → 1–3 lessons appended to `data/learnings.md`, "safe to reset".
Quit Claude, then `bin/ry-yard.sh` again: the SessionStart summary should reflect the yard's state and reuse the running watcher (same pid in `state/.watch.lock`).

## Cleanup

```sh
tmux kill-session -t railyard
kill "$(cat state/.watch.lock)"
git -C projects/<proj> branch | grep ry/   # delete leftovers
```

## What to send me

For each step: worked / didn't, plus any pasted error. Especially step 5's `glab` output and any wake line that came late or never.
