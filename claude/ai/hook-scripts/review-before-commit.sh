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

# Review the checkout the commit runs in: the session's cwd, then a leading `cd <dir> &&` or `git -C <dir> commit` in the command (0.13.0;
# subagents often commit with `cd <worktree> && git commit`, which the hook used to review from the session's directory).
dir="$(printf '%s' "$input" | "$py" -c '
import sys,json,re,shlex,os
d=json.load(sys.stdin); c=d.get("tool_input",{}).get("command",""); w=d.get("cwd") or ""
m=re.match(r"\s*cd\s+(\"[^\"]+\"|\x27[^\x27]+\x27|[^\s;&|]+)\s*&&",c) or re.search(r"git\s+-C\s+(\"[^\"]+\"|\x27[^\x27]+\x27|\S+)\s+commit",c)
if m:
    p=os.path.expanduser(shlex.split(m.group(1))[0]); w=p if os.path.isabs(p) else os.path.join(w or os.getcwd(),p)
print(w)' 2>/dev/null)"
[ -n "$dir" ] && [ -d "$dir" ] && cd "$dir"
hlog() { printf '%s\t%s\t%s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")" "$1" >> "$STATE_DIR/hook.log"; }

# No per-commit review where another review covers it (0.13.0). On 3–4 Oct 2026, 304 commits waited 7.5 h on this hook; builders commit once
# per finding group, and /ai:loop's Stage 4 reviews the whole branch anyway. AI_HOOK_REVIEW_LOOP=1 / AI_HOOK_REVIEW_DOCS=1 bring the review back.
if [ "${AI_HOOK_REVIEW_LOOP:-0}" != 1 ]; then
  br="$(git symbolic-ref --short HEAD 2>/dev/null)"
  if [ -n "$br" ] && [ "$(git config --get "branch.$br.ai-loop" 2>/dev/null)" = on ]; then
    hlog "skipped: loop branch $br"; echo "ai-loop: $br is an /ai:loop branch — no per-commit review (Stage 4 reviews the whole diff)"; exit 0; fi
  case "$(git rev-parse --show-toplevel 2>/dev/null)" in */.claude/worktrees/agent-*)
    hlog "skipped: agent worktree"; echo "ai-loop: subagent worktree — no per-commit review (the loop's Stage 4 or /ai:ship reviews the branch)"; exit 0 ;; esac
fi
changed="$( { git diff HEAD --name-only 2>/dev/null; git ls-files --others --exclude-standard 2>/dev/null; } | sort -u)"
if [ -z "$changed" ]; then hlog "skipped: nothing changed"; echo "ai-loop: nothing changed against HEAD — no review"; exit 0; fi
if [ "${AI_HOOK_REVIEW_DOCS:-0}" != 1 ] && [ -z "$(printf '%s\n' "$changed" | grep -Ev '^docs/|\.(md|mdx|txt)$')" ]; then
  hlog "skipped: docs only"; echo "ai-loop: docs-only change — no review (AI_HOOK_REVIEW_DOCS=1 reviews it)"; exit 0; fi
# New files are part of the change but not of `git diff HEAD`: name them in the prompt (two of the 4 Oct reviews saw an empty diff).
untracked="$(git ls-files --others --exclude-standard 2>/dev/null | head -40 | tr '\n' ' ')"
note="${untracked:+New files not yet tracked by git are part of this change too; read them: $untracked}"

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
  printf '%s\n\nReview the change about to be committed in this repository: run `git diff HEAD` (and `git status` for new files).%s%s Print only the report.\n\nFormat, whatever other writing rules say: line 1 is exactly `REVIEWER: claude reviewer agent (same vendor as the author)`. Line 2 is exactly one of `VERDICT: SHIP`, `VERDICT: NEEDS WORK`, `VERDICT: BLOCK`. The hook reads these two lines; a review without them is lost.\n' \
    "$spec" "${focus:+ Focus especially on: $focus.}" "${note:+ $note}" > "$out.prompt"
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
review="$(CODEX_REVIEW_MODEL="${CODEX_REVIEW_MODEL_COMMIT:-${CODEX_REVIEW_MODEL:-}}" CODEX_REVIEW_EFFORT="${CODEX_REVIEW_EFFORT_COMMIT:-${CODEX_REVIEW_EFFORT:-}}" CODEX_REVIEW_MODEL_RISKY="${CODEX_REVIEW_MODEL_COMMIT_RISKY:-${CODEX_REVIEW_MODEL_COMMIT:-${CODEX_REVIEW_MODEL_RISKY:-}}}" REVIEW_BUDGET="${AI_HOOK_REVIEW_BUDGET:-540}" AI_LANE_TIMEOUT="${AI_HOOK_LANE_TIMEOUT:-400}" AI_STALL_TIMEOUT="${AI_HOOK_STALL_TIMEOUT:-180}" CODEX_STALL_TIMEOUT="${AI_HOOK_CODEX_STALL_TIMEOUT:-300}" REVIEW_NOTE="$note" "$BIN/codex-review" diff HEAD "$focus" 2>"$errf")"; rc=$?
case $rc in
  0) ;;
  75) why="$(grep -m1 '^REVIEWER: none' "$errf" | sed 's/^REVIEWER: none — //; s/ Delegate this review.*//')"
      review="$(claude_fallback)"; crc=$?
      if [ $crc -ne 0 ] || [ -z "$(printf '%s' "$review" | tr -d '[:space:]')" ]; then
        tlog "unreachable"; echo "ai-loop: no reviewer reachable (Claude fallback: $(printf "%s" "${review:-did not answer}" | head -c 160)) — commit allowed without review. $why" >&2; rm -f "$errf"; exit 0
      fi
      echo "ai-loop: Codex and OpenCode unreachable ($why) — reviewed by the Claude reviewer agent instead (same vendor)." >&2
      # A review that ignored the format still counts: read as NEEDS WORK (never BLOCK) instead of being thrown away (all 56 were, 3–4 Oct).
      [ -n "$(printf '%s' "$review" | norm_verdict)" ] || review="$(printf 'REVIEWER: claude reviewer agent (same vendor as the author)\nVERDICT: NEEDS WORK (no verdict line in the review; read it below)\n%s' "$review")" ;;
  *)  tlog "failed"; echo "ai-loop: review failed (exit $rc) — commit allowed. $(head -c 300 "$errf")" >&2; rm -f "$errf"; exit 0 ;;
esac
rm -f "$errf"
verdict="$(printf '%s' "$review" | norm_verdict)"
tlog "${verdict:-none}"
if [ "$verdict" = BLOCK ]; then
  printf 'Independent review blocked this commit. Fix these, then commit again:\n%s\n' "$review" >&2
  exit 2
fi
printf 'ai-loop: %s / VERDICT: %s%s\n' "$(printf '%s' "$review" | sed -n '1p')" "${verdict:-none}" "$([ "$triage" = "-" ] || echo " / jev-triage($mode): $triage")"
exit 0
