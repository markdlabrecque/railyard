---
name: file-ticket
description: Draft a ticket from evidence with a subagent, then file it yourself. Use when a finding deserves its own issue on GitHub or GitLab.
disable-model-invocation: true
---

The research is the expensive half, so a subagent does it. Filing is
outward-facing and lands in the dispatcher's repository under their name, so
**you file, always** — the subagent drafts and never posts. This skill is
self-contained and governs anything filed from the yard, on either host. Where
another ticket-filing skill says to post without asking, this one wins.

## 1. Decide whether to delegate at all

Delegate when the ticket needs evidence you do not already hold — code read, a
command run, history checked, sibling tickets found: more than two tool calls
to gather. Write it yourself when you just finished the work it is about, when
the body is under ~100 words with no file references, or when it is a one-line
follow-up already spelled out in a handoff you just read.

You are a poor judge of this: evidence you half-remember from a diff feels
in-context when it is not. Bias toward delegating.

## 2. Brief the subagent

Six things, and nothing else is needed:

1. **The finding**, one or two sentences, in your own words.
2. **The repository and how to reach it** — a path to run `gh`/`glab` from, or
   an explicit `-R owner/repo` — and which host, since the body pattern and the
   label command differ.
3. **The observed failure verbatim**, command and output. Highest-value input
   in the brief: the subagent cannot reconstruct a transcript it never saw.
4. **One starting point** — a file, a function, or a task id.
5. **What is already decided versus still open.** A subagent cannot infer this,
   and getting it wrong reopens a settled argument in public.
6. **The house style below**, plus `#13`, `#14` and `#16` as the benchmark.

Tell it explicitly to gather the rest itself: file:line citations, counts,
sibling tickets, labels.

## 3. The house style the draft must hit

1. Lead with the observed failure and the real numbers, with exact commands.
2. A cause section naming the mechanism, verifiably, at file:line.
3. **What was ruled out** — the section a delegated ticket is likeliest to
   omit, so brief for it by name. It stops a reader implementing the trap.
4. Decided separated from open, with the reasoning and the accepted cost.
5. File and line for the code that changes, snippet inline, and an instruction
   to find the rest rather than trust the list.
6. Acceptance criteria phrased as observable outcomes, not intentions.

## 4. What comes back — four things, not a URL

1. **The proposed title**: symptom first, then the number that makes it real.
2. **A path to the body file** in the scratchpad. Markdown in a file survives
   shell quoting; a body passed as an argument does not.
3. **Proposed labels**, chosen from the real list (`gh label list` /
   `glab label list --per-page 100`), never invented — on GitLab an invented
   name silently creates a new label.
4. **A three-line evidence block**: what it confirmed and where (file:line),
   what it could **not** confirm, and what it deliberately left out of scope.

Item 4 is load-bearing, and it is the same idea as an engine's inspection
block: you accept on a checkable claim rather than by re-reading the artifact.
"I could not confirm X" is worth more than a confident body.

## 5. Host differences the draft has to respect

**GitLab.** Check `ls .gitlab/issue_templates/` first: when a template fits
(`Bug.md`, `Task.md`), its headings are the agreed shape and they replace the
house style above. Fill every section it defines; one with nothing to say gets
an explicit `None`, never the placeholder text. Reference siblings as bare
`#305` — GitLab links them. `glab` has no body-file flag, so the body is passed
as `-d "$(cat <body-file>)"`.

**GitHub.** No templates to check for railyard's own repos. `gh` does take a
body file, `-F`. A pull request is `#N` in issue text, so the autolink works.

## 6. File it

Skim the title and opening paragraph the way a human would — that skim is only
possible before the post. Check the one CLI you are about to use is present,
not both:

```shell
command -v gh   >/dev/null || { echo "gh is not on PATH"; exit 1; }
gh issue create -R <owner/repo> -t "<title>" -F <body-file> -l <labels>
```

```shell
command -v glab >/dev/null || { echo "glab is not on PATH"; exit 1; }
glab issue create -y --no-editor -R <owner/repo> -t "<title>" -d "$(cat <body-file>)" -l <labels>
```

Report the ticket to the dispatcher as `<project> #N` with the full URL, plus the one
line the subagent could not confirm.
