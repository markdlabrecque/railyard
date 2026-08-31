# Railyard

Railyard runs Claude Code agents on your repos — one isolated git worktree per
task — and keeps you in the loop for every decision that matters.

You are the **dispatcher**. The session you talk to is the **yardmaster**; it
reads your projects and never edits them. Every change is an **engine's** job,
worked in its own **siding**.

```sh
bin/ry-yard.sh          # open the yard
```

Then talk to it. [`docs/guide.md`](docs/guide.md) is the guide.

## Which document is which

Railyard is used by agents, not driven by hand, so most of its documentation is
written for them. These are the ones written for you:

| document | for | what it is |
| --- | --- | --- |
| [`docs/guide.md`](docs/guide.md) | you | how to use railyard day to day |
| [`docs/prd.md`](docs/prd.md) | you, and agents | every feature, and why it is built that way |
| [`docs/test-plan.md`](docs/test-plan.md) | you | manual script for proving the loop on a real project |
| [`CONTEXT.md`](CONTEXT.md) | everyone | the vocabulary — one meaning per term |
| [`AGENTS.md`](AGENTS.md) | the yardmaster | its operating contract, loaded every turn |
| [`templates/engine-preamble.md`](templates/engine-preamble.md) | every engine | the rules it gets before its waybill |
| [`.claude/skills/`](.claude/skills/) | the yardmaster | `/manifest` `/dispatch` `/allaboard` `/shed` |

Change how an agent behaves in `AGENTS.md`, the preamble, or a skill — never in
`docs/`. Nothing in `docs/` is loaded into an agent's context automatically.

## Layout

```
projects/<name>/        clones of your repos
yard/<project>/<id>/    sidings — one worktree per task
state/                  live task state, inbox, events
data/                   survey reports, learnings, project register
bin/                    the ry-* scripts (every one takes -h)
```

## Tests

```sh
bats tests              # 172 ok
shellcheck bin/ry-*.sh
```
