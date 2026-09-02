---
name: manifest
description: The manifest — every task by status, plus unread inbox count.
disable-model-invocation: true
---

Run `bin/ry-manifest.sh` and show its output verbatim in a code block. Below it, one line per task that needs a dispatcher decision (turn-ended hauls awaiting merge/PR word, BLOCKED engines, failed checks, STRANDED queued tasks), phrased as the decision, with every ticket, PR or MR named per AGENTS.md § Reporting style — project word first, full URL on first mention (`bin/ry-ref.sh <id>` prints both). If nothing needs a decision, say so in one line.

Then process `data/learnings.md` per AGENTS.md § Learnings: nothing to say if it has no `- ` lines, otherwise the whole queue in one message, promote-or-drop.
