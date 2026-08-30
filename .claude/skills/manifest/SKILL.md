---
name: manifest
description: The manifest — every task by status, plus unread inbox count.
disable-model-invocation: true
---

Run `bin/ry-manifest.sh` and show its output verbatim in a code block. Below it, one line per engine that needs a dispatcher decision (turn-ended hauls awaiting merge/PR word, BLOCKED engines, failed checks), phrased as the decision. If nothing needs a decision, say so in one line.
