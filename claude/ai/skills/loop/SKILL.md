---
name: loop
description: Use when asked to build a real feature end to end. Plans a spec, has an independent reviewer challenge it, implements on Sonnet with DeepSeek doing the rote parts, then independent QA. Not for anything smaller than a real feature.
disable-model-invocation: true
---
Run the full loop for: $ARGUMENTS

Conventions: specs live at the repo root as `SPEC-<slug>.md`. Never overwrite an existing spec — pick a new slug. The helper commands below are on PATH while the `ai` plugin is enabled. The first output line of every helper names who actually did the work (`WORKER:` / `REVIEWER:`); carry those names into the final report.

Stage 1 — Plan (you, at the tier you're running). Write `SPEC-<slug>.md`: files to touch with exact paths, interfaces, edge cases, existing patterns to copy (name the file), and a "Done means" list where every item is verifiable (tests, build, observable behaviour). If a folder the change touches has a nested `AGENTS.md` of gotchas, read it and name in the spec which of its lines apply. For research first ("how does the existing auth middleware work"), delegate to the `grunt` agent rather than reading everything yourself.

Stage 2 — Challenge the spec (independent reviewer). Run in Bash:
  codex-review spec SPEC-<slug>.md
Codex reviews it; if Codex is at its limit the script falls back to an OpenCode Go model on its own. If it exits with code 75, no external reviewer is reachable: delegate the same review to the `reviewer` agent and mark that review as same-vendor in the report.
Waiting rule for every `codex-review` call: run it as a background Bash command (a review often outlasts the 10-minute Bash ceiling) and read its stderr while it runs — it prints a heartbeat every minute. It stops by itself: a lane that reports a limit is dropped within seconds, a silent lane after 5 minutes (10 for Codex), the whole call after 25 minutes. So never wait longer than 25 minutes, and if the task outlives that or the heartbeat stops for 3 minutes, kill it and treat it as exit 75. The exit-75 line says when each lane is usable again ("codex back Tue 09:51"); copy that into the report, and do not call `codex-review` again in this session before that time unless I ask.
Fold the findings that hold up into the spec; list the ones you rejected, with the reason. Show me the revised spec and the verdict. Do not continue without my yes.

Stage 3 — Build. Delegate to the `implementer` agent with the spec path as its brief. It builds on Sonnet and sends mechanical, precisely specified chunks to DeepSeek through `grunt-run` itself — falling over to other OpenCode models, and finally doing the chunk on Sonnet if every cheap lane is limited. You do not need to split that work for it.

Stage 4 — QA (independent reviewer). Run in Bash:
  codex-review diff <base-branch> [focus]
For anything touching auth, payments, schemas or data, pass a focus: `codex-review diff main "auth flows, payment state, data loss"`. A focus also selects the stronger Codex tier when `CODEX_REVIEW_MODEL_RISKY` is set, so pass one only when the diff warrants it. Same fallback rule as Stage 2 (exit 75 → `reviewer` agent, flagged). Show me the verdict.

Stage 5 — Fix loop, at most two rounds, back through the `implementer` with the findings as its brief, then re-run Stage 4. On a second BLOCK, stop and show me why instead of retrying.

Gotchas: if QA found a mistake that will recur in that folder (not a one-off bug), propose one line for the nearest nested `AGENTS.md`, as a fact with the check that catches it. Show it to me; add it only on my yes. A folder getting its first gotchas file also gets a one-line `CLAUDE.md` containing `@AGENTS.md`, because Claude Code does not read a nested `AGENTS.md` in a repo that has a root `CLAUDE.md`.

Never merge. Report: files changed, both verdicts with the name of the reviewer that produced each, which chunks went to the cheap lane and on which model, and anything still ambiguous.
