#!/usr/bin/env bash
# Regression check (0.22.4): the loop's worktree cleanup removes a merged worktree whose only untracked entry is a
# node_modules symlink, and keeps a tree with real changes. Before 0.22.4 the loop ran `git worktree remove` alone,
# which refused assigame-next's tablet-duo-layout-3 six times (31 Oct to 1 Nov 2026): `mobile/.gitignore` says
# `node_modules/`, which matches directories only. No model call. Run: bash claude/ai/evals/wt-clean.sh  (exit 0 = pass)
set -euo pipefail
bin="$(cd "$(dirname "$0")/../bin" && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
g() { git -c user.name=t -c user.email=t@local "$@"; }
mkdir -p "$T/repo/mobile/node_modules/pkg" && cd "$T/repo"
git init -q -b main; printf 'node_modules/\n' > mobile/.gitignore; printf 'a\n' > a.txt
g add a.txt mobile/.gitignore; g commit -qm init
for b in linked dirty open; do g worktree add -q ".claude/worktrees/$b" -b "feat/$b" main; done
ln -s "$T/repo/mobile/node_modules" .claude/worktrees/linked/mobile/node_modules
printf 'x\n' > .claude/worktrees/dirty/notes.txt
(cd .claude/worktrees/open && printf 'b\n' > b.txt && g add b.txt && g commit -qm open)
printf '.claude/\n' >> .git/info/exclude

# The old step: a plain remove refuses the symlinked tree.
if git worktree remove .claude/worktrees/linked 2>/dev/null; then echo "FAIL: setup, plain remove did not refuse the symlink"; exit 1; fi

out="$("$bin/ai-wt-clean" main)"; echo "$out"
fail=0
[ ! -e .claude/worktrees/linked ] || { echo "FAIL: merged tree with a node_modules symlink is still there"; fail=1; }
[ -d mobile/node_modules/pkg ] || { echo "FAIL: the symlink target was deleted"; fail=1; }
[ -f .claude/worktrees/dirty/notes.txt ] || { echo "FAIL: a tree with an untracked file was removed"; fail=1; }
[ -d .claude/worktrees/open ] || { echo "FAIL: an unmerged tree was removed"; fail=1; }
grep -q 'kept, has changes: .claude/worktrees/dirty' <<<"$out" || { echo "FAIL: the kept tree is not reported"; fail=1; }
[ "$fail" = 0 ] && echo "PASS"
exit "$fail"
