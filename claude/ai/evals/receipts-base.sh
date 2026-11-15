#!/usr/bin/env bash
# Regression check (0.22.8): ai-night receipts find the base a handoff names, and a repo without main still gets a verdict.
# Before 0.22.8 the parser read only ", base `x`". assigame-next writes " · base `develop`" and has no main, so its four
# receipts of 11 Nov 2026 said base "main" and stayed "pending" after the three specs merged into develop.
# No model call. Run: bash claude/ai/evals/receipts-base.sh  (exit 0 = pass)
set -euo pipefail
bin="$(cd "$(dirname "$0")/../bin" && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
g() { git -c user.name=t -c user.email=t@local "$@"; }
mkdir -p "$T/repo/docs/tasks" && cd "$T/repo"
git init -q -b develop; printf 'a\n' > a.txt; g add a.txt; g commit -qm init
g switch -qc feat/one; printf 'b\n' > b.txt; g add b.txt; g commit -qm one; tip="$(git rev-parse HEAD)"
g switch -q develop; g merge -q --no-ff -m "Merge branch 'feat/one'" feat/one
cat > docs/tasks/x-handoff.md <<'MD'
## 1. one
- Branch: `feat/one` · base `develop` · worktree `.claude/worktrees/one`
Status: shipped

## 2. two
- Branch: `feat/two`. Worktree: `.claude/worktrees/two`. Base: develop (merge commit)
Status: approved

## 3. three
- Branch: `feat/three`, base `feat/one`
Status: approved

## 4. four
- Branch: `feat/four`
Status: approved
MD
out="$(python3 -I - "$bin" "$T/repo" "$tip" <<'PY'
import datetime as dt, sys
sys.path.insert(0, sys.argv[1]); import _receipts as R
repo, tip = sys.argv[2], sys.argv[3]
print("bases", [s[2] for s in R.handoff_specs(repo + "/docs/tasks/x-handoff.md")])
old = {"date": "2026-11-11", "repo_path": repo, "tip": tip, "base": "main", "commits": None}
print("stored-main", R.verdict(old, dt.date(2026, 11, 15)))
print("no-base", R.resolve_base(repo, None) if hasattr(R, "resolve_base") else "missing")
PY
)"; echo "$out"
# The write path, as ai-night calls it: spec 1 went approved → shipped.
printf '{}' > "$T/out.json"
python3 -I "$bin/_receipts.py" write "$T/rc" "$T/out.json" "$T/repo" "$T/repo/docs/tasks/x-handoff.md" 1 ok 60 \
  "approved approved approved approved" "shipped approved approved approved"
w="$(python3 -I -c 'import glob,json,sys; d=json.load(open(glob.glob(sys.argv[1]+"/*/*.json")[0])); print("write", d["spec"], d["base"], d["tip"] == sys.argv[2])' "$T/rc" "$tip")"
echo "$w"; out="$out"$'\n'"$w"
fail=0
grep -qx "write one develop True" <<<"$out" || { echo "FAIL: the written receipt does not name base develop and the branch tip"; fail=1; }
grep -qx "bases \['develop', 'develop', 'feat/one', None\]" <<<"$out" || { echo "FAIL: handoff bases not parsed"; fail=1; }
grep -qx "stored-main accepted" <<<"$out" || { echo "FAIL: a receipt with base main in a repo without main is not accepted"; fail=1; }
grep -qx "no-base develop" <<<"$out" || { echo "FAIL: no base does not fall back to the repo's branch"; fail=1; }
[ "$fail" = 0 ] && echo "PASS"
exit "$fail"
