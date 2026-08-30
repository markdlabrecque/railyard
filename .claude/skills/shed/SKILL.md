---
name: shed
description: End-of-session sweep — file durable lessons and loose task state before context resets.
disable-model-invocation: true
---

1. Sweep the visible session for durable knowledge: a project convention learned the hard way, a tool gotcha, a waybill pattern that worked or failed. Append each as one dated line to `data/learnings.md`. Session-specific detail (which id did what) stays out.
2. Check `bin/ry-manifest.sh`. For each engine whose next step is known but not yet recorded, write it as the final line of `state/<id>.waybill.md` prefixed `NEXT:` so a fresh session can resume.
3. Run `bin/ry-inbox.sh`; unread lines get handled now or named to the dispatcher explicitly.
4. Report in three lines: lessons filed, engines with a recorded NEXT, anything unresolved. Then state whether the session is safe to reset.
