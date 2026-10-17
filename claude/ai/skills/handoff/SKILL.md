---
name: handoff
description: Use when the session's context is large (the band warns at 300k tokens) or a piece of work is done and the next one is different. Writes a handoff note to docs/tasks/ so a new session can continue without this session's history.
disable-model-invocation: true
---
Write a handoff for: $ARGUMENTS (default: the work in progress in this session).

Every model call re-reads the whole conversation. On 10–17 Oct 2026, 14 main sessions passed 500k tokens and used about a third of the week's Claude quota. A new session that starts from a short note costs a fraction of that.

1. If an `/ai:loop` batch handoff (`docs/tasks/<batch>-handoff.md`) covers this work, update its section instead of writing a new file.
2. Otherwise write `docs/tasks/<slug>-handoff.md` (create the folder if missing). Keep it under about 80 lines. Sections:
   - Goal: what I asked for, in one or two sentences, and what "done" means.
   - State: what is done, what is in progress, what is left, in order.
   - Decisions: what I decided or answered, and approaches that were tried and dropped, with the reason.
   - Where: repo, branch, base, worktree path, the spec or plan files, commits and PRs.
   - Checks: the commands that prove it works (tests, build, e2e) and their last result.
   - Open: review findings not fixed, questions for me, risks.
   - Next step: the first concrete action for the next session.
3. Commit nothing unless I say so. Name in the note any uncommitted change it depends on.
4. Reply with the path and the line to paste into a new session: `Read docs/tasks/<slug>-handoff.md and continue from "Next step".`
