---
name: ship
description: Use when asked to ship, finish or wrap up the current branch. Independent review of the diff, fix what holds up, commit. Not for building features (that is /ai:loop).
disable-model-invocation: true
---
Wrap up the current branch: $ARGUMENTS

1. Run in Bash: `codex-review diff <base>` (base = the branch this one was cut from; if unsure, omit it and the script uses the repo's default branch). If it exits 75, delegate the review to the `reviewer` agent and flag it as same-vendor, and repeat in your report the line saying when each lane is usable again. Run it in the background and watch its once-a-minute heartbeat on stderr; it ends by itself within 25 minutes (limits are caught in seconds, silence after 5–10 minutes), so never wait longer than that.
2. Fix every BLOCK finding and the NEEDS WORK findings you agree with; list the ones you rejected and why. If a finding is a mistake that will recur in that folder, propose one line for the nearest nested `AGENTS.md` gotchas file (add it only on my yes).
3. Re-run the review once. Then run the tests and the build yourself; do not rely on the reviewer for that.
4. Commit with a message that summarises the change and ends with the verdict line. Because a review just ran, prefix the commit so the pre-commit hook doesn't run a second one: `AI_LOOP_SKIP_REVIEW=1 git commit -m "..."`. Do not push or merge unless I say so.
