# shared by grunt-run / codex-review / ai-limits (bash 3.2 compatible — macOS default bash)
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/ai-loop"; mkdir -p "$STATE_DIR"
_BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_PY="$(command -v python3 2>/dev/null || echo /usr/bin/python3)"
COOLDOWN="${AI_LIMIT_COOLDOWN:-1800}"        # skip a limited lane this long ONLY when it did not say when it resets (30 min)
STALL_COOLDOWN="${AI_STALL_COOLDOWN:-900}"   # skip a lane this long after it went silent or ran out of time (15 min)
STALL_TIMEOUT="${AI_STALL_TIMEOUT:-300}"     # kill a lane that has produced no output at all for this long
LANE_TIMEOUT="${AI_LANE_TIMEOUT:-1200}"      # kill a lane that is still running after this long, whatever it prints
POLL="${AI_LANE_POLL:-2}"
MAX_SKIP=$(( 8 * 86400 ))                    # never believe a reset further away than this (weekly windows are 7 days)

# Any wording that means "limit", used on the output of a command that has already failed.
LIMIT_RE='rate.?limit|usage.?limit|limit (has been |was )?(reached|exceeded|hit)|hit your (usage|weekly|5-hour)|quota|\b429\b|too many requests|insufficient (balance|credit|funds)|resource.?exhausted|out of credits'
# Only wording that means "this account is out until a reset", used WHILE a command runs. A passing 429 must not match: the CLI retries those itself.
HARD_LIMIT_RE='hit your usage limit|usage_limit_exceeded|usage limit (has been |was )?(reached|exceeded)|UsageLimitError|exceeded retry limit|insufficient (balance|credit|funds)|out of credits|quota (has been |was )?(exceeded|exhausted)|resets in [0-9]'

now() { date +%s; }
mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0; }  # GNU first (fails on macOS → BSD form)
lane_key() { printf '%s/%s.limited' "$STATE_DIR" "$(printf '%s' "$1" | tr '/:' '__')"; }
provider_of() { case "$1" in */*) printf '%s' "${1%%/*}" ;; esac; }
is_limited_msg() { grep -Eiq "$LIMIT_RE" "$1"; }
fmt_clock() { date -r "$1" '+%a %H:%M' 2>/dev/null || date -d "@$1" '+%a %H:%M' 2>/dev/null || echo "?"; }  # BSD first: GNU `date -r` wants a file
fmt_dur() { local s=$1; [ "$s" -lt 0 ] && s=0
  if [ "$s" -ge 86400 ]; then echo "$(( s / 86400 ))d $(( s % 86400 / 3600 ))h"
  elif [ "$s" -ge 3600 ]; then echo "$(( s / 3600 ))h $(( s % 3600 / 60 ))m"
  elif [ "$s" -ge 60 ]; then echo "$(( s / 60 )) min"
  else echo "${s}s"; fi; }

# State file per lane: line 1 = epoch until which the lane is skipped, line 2 = how we know (reported | guessed | stalled | timeout | usage-snapshot), line 3 = the lane's own words.
_own_until() { local f u; f="$(lane_key "$1")"; [ -f "$f" ] || { echo 0; return; }
  u="$(sed -n '1p' "$f" | tr -cd '0-9')"; [ -n "$u" ] || u=$(( $(mtime "$f") + COOLDOWN ))   # empty file = written by plugin ≤ 0.3.0
  echo "$u"; }
lane_until() { local u p pu; u="$(_own_until "$1")"; p="$(provider_of "$1")"   # a model is also out while its whole provider is out
  if [ -n "$p" ]; then pu="$(_own_until "$p")"; [ "$pu" -gt "$u" ] && u="$pu"; fi; echo "$u"; }
recently_limited() { [ "$(lane_until "$1")" -gt "$(now)" ]; }
lane_how() { local f; f="$(lane_key "$1")"; [ -f "$f" ] && sed -n '2p' "$f"; }
lane_back() { local u; u="$(lane_until "$1")"; echo "$(fmt_clock "$u") (in $(fmt_dur $(( u - $(now) ))))"; }   # "Tue 14:32 (in 2h 13m)"

# mark_limited <lane> [limit|stalled|timeout|usage-snapshot] [file-with-the-lane's-output | epoch]...
mark_limited() { local lane="$1" kind="${2:-limit}" until="" how why="" n; [ $# -gt 0 ] && shift; [ $# -gt 0 ] && shift; n="$(now)"
  case "$kind" in
    limit) until="$("$_PY" "$_BIN/_limits.py" reset "$@" 2>/dev/null | sed -n '1p' | tr -cd '0-9')"
           why="$(cat "$@" 2>/dev/null | grep -Eio ".{0,80}($HARD_LIMIT_RE).{0,120}" | tail -1)"
           [ -n "$why" ] || why="$(cat "$@" 2>/dev/null | grep -Eio ".{0,80}($LIMIT_RE).{0,120}" | tail -1)"
           if [ -n "$until" ]; then how=reported; else how=guessed; until=$(( n + COOLDOWN )); fi ;;
    usage-snapshot) until="$(printf '%s' "${1:-}" | tr -cd '0-9')"; how="$kind"; why="Codex's own usage data shows a window at 100%"; [ -n "$until" ] || until=$(( n + COOLDOWN )) ;;
    *)     until=$(( n + STALL_COOLDOWN )); how="$kind" ;;
  esac
  [ "$until" -gt $(( n + MAX_SKIP )) ] && until=$(( n + MAX_SKIP ))
  printf '%s\n%s\n%s\n' "$until" "$how" "$why" > "$(lane_key "$lane")"; }

_tree() { local c; for c in $(pgrep -P "$1" 2>/dev/null); do _tree "$c"; done; echo "$1"; }
kill_tree() { local pids; pids="$(_tree "$1")"; kill -TERM $pids 2>/dev/null; sleep 1; kill -KILL $pids 2>/dev/null; wait "$1" 2>/dev/null; return 0; }
_size() { local a b; a="$(wc -c < "$1" 2>/dev/null | tr -d ' ')"; b="$(wc -c < "$2" 2>/dev/null | tr -d ' ')"; echo $(( ${a:-0} + ${b:-0} )); }

# live_limit_seen <out> <err> — true as soon as the running CLI says the account is out.
# Looks at stderr (both CLIs put errors and logs there) and at error events of `codex exec --json` on stdout — never at review text or diff
# lines, which may quote these very phrases (lines starting with space, + or - are skipped for the same reason).
live_limit_seen() {
  grep -E '^[^ +-]' "$2" 2>/dev/null | grep -Eiq "$HARD_LIMIT_RE" && return 0
  grep -E '^\{"type":"(error|turn\.failed)"' "$1" 2>/dev/null | grep -Eiq "$HARD_LIMIT_RE"; }

# failed_on_limit <out> <err> — for a command that has already failed: was a limit the reason? Broad wording on stderr (diff-like lines skipped);
# on stdout only error events, or hard-limit wording when stdout is a short error rather than a review.
failed_on_limit() { grep -E '^[^ +-]' "$2" 2>/dev/null | grep -Eiq "$LIMIT_RE" && return 0
  live_limit_seen "$1" "$2" && return 0
  [ "$(wc -c < "$1" 2>/dev/null | tr -d ' ')" -lt 4000 ] && grep -Eiq "$HARD_LIMIT_RE" "$1" 2>/dev/null; }

# run_lane <label> <out> <err> <command...>
# Runs the command with a watchdog. Returns the command's own exit code, or: 200 = it reported a hard limit while running (killed at once),
# 201 = no output for STALL_TIMEOUT (killed), 202 = still running after LANE_TIMEOUT (killed). Prints a heartbeat on stderr every minute.
run_lane() { local label="$1" out="$2" err="$3"; shift 3
  "$@" >"$out" 2>"$err" </dev/null &
  local pid=$! start n size prev=-1 changed beat; start="$(now)"; changed="$start"; beat="$start"
  while kill -0 "$pid" 2>/dev/null; do
    sleep "$POLL"; n="$(now)"; size="$(_size "$out" "$err")"
    if [ "$size" != "$prev" ]; then prev="$size"; changed="$n"
      if live_limit_seen "$out" "$err"; then kill_tree "$pid"; echo "$label: limit reported after $(( n - start ))s — stopped waiting" >&2; return 200; fi
    fi
    if [ $(( n - changed )) -ge "$STALL_TIMEOUT" ]; then kill_tree "$pid"; echo "$label: silent for $(fmt_dur "$STALL_TIMEOUT") — killed (a CLI retrying a limit in silence looks like this)" >&2; return 201; fi
    if [ $(( n - start )) -ge "$LANE_TIMEOUT" ]; then kill_tree "$pid"; echo "$label: still running after $(fmt_dur "$LANE_TIMEOUT") — killed" >&2; return 202; fi
    if [ $(( n - beat )) -ge 60 ]; then beat="$n"; echo "$label: working, $(fmt_dur $(( n - start ))) so far, last output $(( n - changed ))s ago" >&2; fi
  done
  wait "$pid"; }

# Free OpenCode models (plugin 0.6.0). OPENCODE_FREE_MODELS="opencode/<id>-free …" (aliases.zsh) lists models that cost nothing right now;
# grunt-run tries them before GRUNT_MODELS and codex-review before REVIEW_FALLBACK_MODELS. A repo opts out with `git config ai-loop.freelane off`
# (most free models may train on what they are sent). free_models [dir] prints the usable ones: listed, not skipped, repo not opted out.
free_models() { local m
  [ -n "${OPENCODE_FREE_MODELS:-}" ] || return 0
  [ "$(git ${1:+-C "$1"} config --get ai-loop.freelane 2>/dev/null)" = off ] && return 0
  for m in $OPENCODE_FREE_MODELS; do recently_limited "$m" || printf '%s ' "$m"; done; }
is_free() { case " ${OPENCODE_FREE_MODELS:-} " in *" $1 "*) return 0 ;; esac; return 1; }
