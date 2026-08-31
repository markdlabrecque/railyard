# Learnings

- 2026-08-30 — A delivery mode that dispatch accepts but nothing downstream can honour strands the task after the work is done. Validate deliverability at dispatch, not at delivery.
- 2026-08-30 — no-mistakes is a git proxy: one binary per machine, but `no-mistakes init` per repo and a `.no-mistakes.yaml` committed at the repo root. Anything wrapping it belongs on the project's line in `data/projects.md`, not on the yard.
- 2026-08-30 — When one backend knows more than the shared contract, give it a narrower question to answer rather than its own path into the status file. Backends that cannot answer return false and the existing timer still works.
- 2026-08-30 — Config that belongs to the yard goes in a file the yard owns; keep the environment variable as the override so the test suite and one-off runs are unaffected.
- 2026-08-30 — Check that `git merge --no-ff` actually produced a merge commit. It has silently fast-forwarded here, and the branch content lands either way, so the history is wrong without anything failing.
