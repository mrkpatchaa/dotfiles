---
name: test-audit
description: Use when asked to audit, prune or clean up a repo's tests. Finds low-value tests (restating the code, copied fixtures, test-only seams, duplicates of a stronger test), reports evidence first, deletes one coherent batch only after my yes.
disable-model-invocation: true
---
Audit the tests in: $ARGUMENTS (default: the whole repo).

The goal is confidence per line of test, not a deletion count.

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

Stage 4 — Consolidate (optional, only on my yes, after the deletions). Shrink what stays without losing what it checks, one folder per commit:
- one-test-per-row matrices become `[input, expected]` tables asserted together, written so a failure still names the row;
- tests with identical setup merge into one workflow test when the repo's testing notes allow it;
- repeated inline objects become `make*`/`seed*` builders in the same file, with expected values kept literal;
- hand-rolled fakes of a database or service become the real thing where the repo can run it (SQLite or a local Supabase with migrations);
- money, credits, limits and cross-user isolation assertions stay exact or get stricter, never looser.
Measure line and branch coverage before and after with the repo's coverage command; report both, and restore any source file that lost coverage before committing.
