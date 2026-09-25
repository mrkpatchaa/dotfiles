---
name: test-audit
description: Use when asked to audit, prune or clean up a repo's tests. Finds low-value tests (restating the code, copied fixtures, test-only seams, duplicates of a stronger test), reports evidence first, deletes one coherent batch only after my yes.
disable-model-invocation: true
---
Audit the tests in: $ARGUMENTS (default: the whole repo).

Adapted from OpenClaw's test-audit skill (github.com/openclaw/openclaw, .agents/skills/test-audit), which removed about 400k lines of tests without a meaningful drop in coverage. The goal is confidence per line of test, not a deletion count.

Read the root and nested `AGENTS.md` first. Keep this read-only until stage 3.

Stage 1 — Inventory (cheap lane). Delegate to the `grunt` agent: list test files per package with line counts, the date each was added (`git log --diff-filter=A --format=%as -- <file>`), how many were added in the last 60 days, and the e2e suites that exist. It returns a table, not file contents.

Stage 2 — Candidates (you). Pick one package or folder at a time, starting where recent agent-written tests cluster. For each candidate test, read the whole test, the production code it covers and that code's callers. A test is a candidate when it matches one of these:
- it asserts implementation, not behaviour: it would fail under a refactor that keeps behaviour;
- the expected value is produced by the helper under test, or a mock implements the behaviour being asserted;
- self-comparisons, assertion-free "coverage" tests, snapshot or string greps of the source;
- copied fixtures, inventories or export lists with no assertion of their own;
- the same contract asserted again at a lower layer when a test at the real boundary (e2e, route, edge function) already covers it;
- it exists only to keep a test-only export, flag or wrapper alive — then that seam is dead code too;
- its name promises more than it checks.
Keep a test when it is the only guard of a public API, schema or migration, auth or payment rule, storage format, a default, observable call ordering, or a regression that once happened. Slow or old is not a reason to delete.

Record for every candidate: file and test name; what failure it can actually detect; the stronger test that still covers it (or why nothing needs to); non-test callers of any seam it keeps alive; why it exists (`git log -S` or blame). A missing field means it stays.

Show me the candidates as a table (file · test · why low value · what still covers it · lines removed), with the tests you looked at and kept listed separately. Do not continue without my yes.

Stage 3 — One batch. On my yes, delete that batch only (one package or folder), plus any test-only exports and dead code it frees. Do not add replacement tests. Do not edit files while a test runner is running. Run that package's test command and type check, then `git diff --numstat`, and report test lines and production lines removed separately. A kept test that now fails is a possible product bug: reproduce it and tell me; never delete it to go green. The pre-commit review runs on the commit as usual.

Then offer the next folder; one batch per commit.
