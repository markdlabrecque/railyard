---
name: dispatch
description: Dispatch one engine from a plain request — "/dispatch <project> <task>".
disable-model-invocation: true
---

Follow AGENTS.md § Task lifecycle, Intake through Dispatch, for exactly one engine. The first word of the argument is the project; the rest is the task. Infer shape from the verb (investigate/why/compare → survey; fix/add/change → haul) and mode from `data/projects.md`, defaulting to `local-only`. The base branch resolves itself from `data/projects.md`; pass `--base <branch>` only when the dispatcher names one for this task. Write a full waybill, dispatch, and reply with one line: shape, mode, base, id.
