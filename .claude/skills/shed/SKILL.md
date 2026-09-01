---
name: shed
description: End-of-session sweep — file durable lessons and loose task state before context resets.
disable-model-invocation: true
---

1. Sweep the visible session for durable knowledge: a project convention learned the hard way, a tool gotcha, a waybill pattern that worked or failed. Append each as one dated line to `data/learnings.md`. Session-specific detail (which id did what) stays out, and so does design rationale about railyard itself — that belongs in `docs/prd.md`. The file is a queue: the next session start, `/manifest` or `/allaboard` will promote or drop every line you file, so file what you would defend, not what you might want later.
2. Check `bin/ry-manifest.sh`. For each engine whose next step is known but not yet recorded, write it as the final line of `state/<id>.waybill.md` prefixed `NEXT:` so a fresh session can resume.
3. Run `bin/ry-inbox.sh`; unread lines get handled now or named to the dispatcher explicitly.
4. Write `state/open-decisions.md`: one line each for every item still awaiting the dispatcher's word — an unanswered decision, an ask discussed but never dispatched, or a review judgment a fresh session would otherwise have to re-derive. Carry the task id where there is one.
5. Report in three lines: lessons filed, engines with a recorded NEXT, anything unresolved. Then state whether the session is safe to reset — weighing unfiled learnings, unread inbox lines, and any open decisions still in `state/open-decisions.md`.
