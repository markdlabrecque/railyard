---
name: manifest
description: The manifest — every task by status, plus unread inbox count.
disable-model-invocation: true
---

Run `bin/ry-manifest.sh`. Its output is already a report: markdown lists grouped by status, one row per task, led by the ticket and project. Paste it as it is, with no code fence around it — a fence turns the lists back into monospace and stops long rows from wrapping. Do not reorder, retype or summarise the rows.

Below it, one line per task that needs a dispatcher decision (turn-ended hauls awaiting merge/PR word, BLOCKED engines, failed checks, stranded queued tasks), phrased as the decision. If nothing needs a decision, say so in one line.

Then process `data/learnings.md` per AGENTS.md § Learnings: nothing to say if it has no `- ` lines, otherwise the whole queue in one message, promote-or-drop.
