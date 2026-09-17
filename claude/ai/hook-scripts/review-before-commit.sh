#!/usr/bin/env bash
# PreToolUse hook (matcher: Bash). Runs one independent review before `git commit` and blocks the commit on VERDICT: BLOCK.
# It never blocks when no reviewer is reachable — it warns and lets the commit through.
# Skip for one commit by prefixing the command: AI_LOOP_SKIP_REVIEW=1 git commit -m "..."
input="$(cat)"
py="$(command -v python3 || echo /usr/bin/python3)"
cmd="$(printf '%s' "$input" | "$py" -c 'import sys,json; print(json.load(sys.stdin).get("tool_input",{}).get("command",""))' 2>/dev/null)"
case "$cmd" in *"git commit"*) ;; *) exit 0 ;; esac
case "$cmd" in *AI_LOOP_SKIP_REVIEW=1*) echo "ai-loop: review skipped for this commit (AI_LOOP_SKIP_REVIEW=1)"; exit 0 ;; esac
BIN="$(cd "$(dirname "$0")/../bin" && pwd)"
errf="$(mktemp)"
review="$("$BIN/codex-review" diff 2>"$errf")"; rc=$?
case $rc in
  0) ;;
  75) echo "ai-loop: no reviewer reachable (Codex and OpenCode limited or missing) — commit allowed without review." >&2; rm -f "$errf"; exit 0 ;;
  *)  echo "ai-loop: review failed (exit $rc) — commit allowed. $(head -c 300 "$errf")" >&2; rm -f "$errf"; exit 0 ;;
esac
rm -f "$errf"
if printf '%s' "$review" | grep -q 'VERDICT: BLOCK'; then
  printf 'Independent review blocked this commit. Fix these, then commit again:\n%s\n' "$review" >&2
  exit 2
fi
printf 'ai-loop: %s / %s\n' "$(printf '%s' "$review" | sed -n '1p')" "$(printf '%s' "$review" | grep -m1 'VERDICT:')"
exit 0
