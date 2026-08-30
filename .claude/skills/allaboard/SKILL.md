---
name: allaboard
description: Recap this session since the dispatcher's last message and walk through open decisions one at a time.
disable-model-invocation: true
---

1. Recap, from the visible session only, what happened after the dispatcher's most recent real message: outcomes landed, engines dispatched or finished, failures, PR URLs in full. Watcher lines (`[railyard] ...`) and hook output are not dispatcher messages.
2. List every dispatcher decision still open anywhere in the visible session, most consequential first. A decision is closed only when a later message plainly resolves it.
3. Present the first open decision with two options max and your recommendation; wait for the answer before presenting the next.
4. With no dispatcher message in the session yet, run `/board` instead of a recap.
