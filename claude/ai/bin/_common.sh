# shared by grunt-run / codex-review / ai-limits (bash 3.2 compatible — macOS default bash)
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/ai-loop"; mkdir -p "$STATE_DIR"
COOLDOWN="${AI_LIMIT_COOLDOWN:-1800}"   # seconds to skip a lane after it reported a limit (30 min)
mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0; }  # GNU first (fails on macOS → BSD form)
lane_key() { printf '%s/%s.limited' "$STATE_DIR" "$(printf '%s' "$1" | tr '/:' '__')"; }
is_limited_msg() { grep -Eiq 'rate.?limit|usage.?limit|limit (has been |was )?(reached|exceeded|hit)|hit your (usage|weekly|5-hour)|quota|\b429\b|too many requests|insufficient (balance|credit|funds)|resource.?exhausted|out of credits' "$1"; }
recently_limited() { local f; f="$(lane_key "$1")"; [ -f "$f" ] && [ $(( $(date +%s) - $(mtime "$f") )) -lt "$COOLDOWN" ]; }
mark_limited() { touch "$(lane_key "$1")"; }
minutes_ago() { echo $(( ( $(date +%s) - $(mtime "$(lane_key "$1")") ) / 60 )); }
