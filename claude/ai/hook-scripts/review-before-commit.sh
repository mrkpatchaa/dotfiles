#!/usr/bin/env bash
# PreToolUse hook (matcher: Bash). Runs one independent review before `git commit` and blocks the commit on VERDICT: BLOCK.
# It never blocks when no reviewer is reachable — it warns and lets the commit through.
# Skip for one commit by prefixing the command: AI_LOOP_SKIP_REVIEW=1 git commit -m "..."
#
# Jev triage (optional, per clone, off by default — the diff is sent to TypeSafe):
#   git config ai-loop.jevtriage shadow   # ask jev-triage too, log both verdicts, change nothing
#   git config ai-loop.jevtriage on       # SKIP skips the review; ADVERSARIAL hands its focus to the reviewer
#   git config --unset ai-loop.jevtriage  # off          (env JEV_TRIAGE=shadow|on works as a fallback)
# Compare the two with: ai-limits triage
input="$(cat)"
py="$(command -v python3 || echo /usr/bin/python3)"
cmd="$(printf '%s' "$input" | "$py" -c 'import sys,json; print(json.load(sys.stdin).get("tool_input",{}).get("command",""))' 2>/dev/null)"
case "$cmd" in *"git commit"*) ;; *) exit 0 ;; esac
case "$cmd" in *AI_LOOP_SKIP_REVIEW=1*) echo "ai-loop: review skipped for this commit (AI_LOOP_SKIP_REVIEW=1)"; exit 0 ;; esac
BIN="$(cd "$(dirname "$0")/../bin" && pwd)"
. "$BIN/_common.sh"

mode="$(git config --get ai-loop.jevtriage 2>/dev/null)"; mode="${mode:-${JEV_TRIAGE:-off}}"
triage="-"; focus=""; tinfo=""
if [ "$mode" = shadow ] || [ "$mode" = on ]; then
  tout="$(git diff HEAD 2>/dev/null | "$BIN/jev-triage" 2>/dev/null)"
  triage="$(printf '%s\n' "$tout" | sed -n '1p')"; triage="${triage:-REVIEW}"
  focus="$(printf '%s\n' "$tout" | sed -n '2p' | sed 's/^focus: //')"
  tinfo="$(printf '%s\n' "$tout" | sed -n '3p')"
fi
tlog() { [ "$triage" = "-" ] || printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$(basename "$PWD")" "$mode" "$triage" "$1" "$tinfo" >> "$STATE_DIR/jev-triage.log"; }

if [ "$mode" = on ] && [ "$triage" = SKIP ]; then
  tlog "not-run"; echo "ai-loop: jev-triage judged this commit trivial — independent review skipped."; exit 0
fi
[ "$mode" = on ] || focus=""      # shadow mode must not change what the reviewer is asked

errf="$(mktemp)"
review="$("$BIN/codex-review" diff "" "$focus" 2>"$errf")"; rc=$?
case $rc in
  0) ;;
  75) tlog "unreachable"; echo "ai-loop: no reviewer reachable (Codex and OpenCode limited or missing) — commit allowed without review." >&2; rm -f "$errf"; exit 0 ;;
  *)  tlog "failed"; echo "ai-loop: review failed (exit $rc) — commit allowed. $(head -c 300 "$errf")" >&2; rm -f "$errf"; exit 0 ;;
esac
rm -f "$errf"
verdict="$(printf '%s' "$review" | grep -m1 -o 'VERDICT: [A-Z ]*' | sed 's/VERDICT: //; s/ *$//')"
tlog "${verdict:-none}"
if printf '%s' "$review" | grep -q 'VERDICT: BLOCK'; then
  printf 'Independent review blocked this commit. Fix these, then commit again:\n%s\n' "$review" >&2
  exit 2
fi
printf 'ai-loop: %s / %s%s\n' "$(printf '%s' "$review" | sed -n '1p')" "$(printf '%s' "$review" | grep -m1 'VERDICT:')" "$([ "$triage" = "-" ] || echo " / jev-triage($mode): $triage")"
exit 0
