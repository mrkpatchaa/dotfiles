#!/usr/bin/env bash
# PreToolUse hook (matcher: Bash). Runs one independent review of the uncommitted changes (git diff HEAD) before `git commit` and blocks
# the commit on VERDICT: BLOCK. The whole branch against its base is /ai:ship's review, not this one (0.12.0; before, every commit on a
# feature branch re-reviewed the branch).
# When Codex and OpenCode are both unreachable (codex-review exit 75), the Claude `reviewer` agent's instructions run headless
# (`claude -p`, read-only tools, flagged same-vendor) if enough of the hook's time is left; AI_HOOK_CLAUDE_FALLBACK=0 turns that off.
# It never blocks when no reviewer at all answers — it warns and lets the commit through.
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

# Headless Claude review with the `reviewer` agent's instructions, used only when codex-review exits 75.
# Prints the review (first line REVIEWER: …, then VERDICT: …) or a short reason, and returns non-zero when there is none.
claude_fallback() {
  [ "${AI_HOOK_CLAUDE_FALLBACK:-1}" = 0 ] && { echo "off (AI_HOOK_CLAUDE_FALLBACK=0)"; return 1; }
  command -v claude >/dev/null 2>&1 || { echo "claude not on PATH"; return 1; }
  local left=$(( ${AI_HOOK_TIMEOUT:-600} - 30 - ( $(now) - T0 ) ))
  [ "$left" -ge 120 ] || { echo "only ${left}s of the hook left"; return 1; }
  local spec out pid t; spec="$(sed '1,/^---$/{/^---$/!d}; 1,/^---$/d' "$BIN/../agents/reviewer.md")"
  out="$(mktemp)"
  printf '%s\n\nReview the change about to be committed in this repository: run `git diff HEAD` (and `git status` for new files).%s Print only the report.\n' \
    "$spec" "${focus:+ Focus especially on: $focus.}" > "$out.prompt"
  claude -p --model "${AI_HOOK_CLAUDE_MODEL:-opus}" --effort "${AI_HOOK_CLAUDE_EFFORT:-high}" \
    --allowedTools "Read,Grep,Glob,Bash(git diff:*),Bash(git log:*),Bash(git show:*),Bash(git status:*)" \
    < "$out.prompt" > "$out" 2>/dev/null &
  pid=$!; t=0
  while kill -0 "$pid" 2>/dev/null; do
    [ "$t" -ge "$left" ] && { kill_tree "$pid"; rm -f "$out" "$out.prompt"; echo "timed out after ${left}s"; return 1; }
    sleep 2; t=$((t + 2))
  done
  wait "$pid"; local rc=$?
  cat "$out"; rm -f "$out" "$out.prompt"; return $rc
}

errf="$(mktemp)"; T0="$(now)"
# A hook must answer before Claude Code's hook timeout (600 s unless the hook entry in .claude/settings.json sets "timeout"), so the review gets
# a smaller budget here than from /ai:loop. With a shorter hook timeout, export AI_HOOK_REVIEW_BUDGET to ~60 s less than it.
# Commit reviews are small and frequent: CODEX_REVIEW_MODEL_COMMIT / _EFFORT_COMMIT (aliases.zsh) replace the ordinary tier here only.
# A focus from jev-triage raises the effort (CODEX_REVIEW_EFFORT_RISKY) but keeps the commit model: an Astra/Sol xhigh review of a big diff
# outlasts this hook (399 s on 23 Sep 2026, killed at the 400 s lane timeout, 7% of the Plus week for no review). CODEX_REVIEW_MODEL_COMMIT_RISKY overrides.
review="$(CODEX_REVIEW_MODEL="${CODEX_REVIEW_MODEL_COMMIT:-${CODEX_REVIEW_MODEL:-}}" CODEX_REVIEW_EFFORT="${CODEX_REVIEW_EFFORT_COMMIT:-${CODEX_REVIEW_EFFORT:-}}" CODEX_REVIEW_MODEL_RISKY="${CODEX_REVIEW_MODEL_COMMIT_RISKY:-${CODEX_REVIEW_MODEL_COMMIT:-${CODEX_REVIEW_MODEL_RISKY:-}}}" REVIEW_BUDGET="${AI_HOOK_REVIEW_BUDGET:-540}" AI_LANE_TIMEOUT="${AI_HOOK_LANE_TIMEOUT:-400}" AI_STALL_TIMEOUT="${AI_HOOK_STALL_TIMEOUT:-180}" CODEX_STALL_TIMEOUT="${AI_HOOK_CODEX_STALL_TIMEOUT:-300}" "$BIN/codex-review" diff HEAD "$focus" 2>"$errf")"; rc=$?
case $rc in
  0) ;;
  75) why="$(grep -m1 '^REVIEWER: none' "$errf" | sed 's/^REVIEWER: none — //; s/ Delegate this review.*//')"
      review="$(claude_fallback)"; crc=$?
      if [ $crc -ne 0 ] || ! printf '%s' "$review" | grep -q 'VERDICT:'; then
        tlog "unreachable"; echo "ai-loop: no reviewer reachable (Claude fallback: $(printf "%s" "${review:-did not answer}" | head -c 160)) — commit allowed without review. $why" >&2; rm -f "$errf"; exit 0
      fi
      echo "ai-loop: Codex and OpenCode unreachable ($why) — reviewed by the Claude reviewer agent instead (same vendor)." >&2 ;;
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
