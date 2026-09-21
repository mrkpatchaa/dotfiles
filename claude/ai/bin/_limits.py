#!/usr/bin/env python3
"""_limits.py — helpers for the limit tracking in _common.sh (stdlib only; every path fails open by printing nothing).

  _limits.py reset FILE...          epoch (seconds) at which the limit described in these outputs lifts, if they say so
  _limits.py codex-usage            last usage snapshot Codex itself wrote to its session files (no request is made)
  _limits.py codex-usage --exhausted [--since EPOCH]   epoch at which Codex is usable again, only if that snapshot shows a window at 100%
  _limits.py codex-last FILE        last agent message from `codex exec --json` output (used when -o wrote nothing)
"""
import glob, json, os, re, sys, time

NOW = time.time()
MONTHS = {m: i + 1 for i, m in enumerate("jan feb mar apr may jun jul aug sep oct nov dec".split())}
UNIT = {"d": 86400, "h": 3600, "m": 60, "s": 1}
DUR_TOKEN = r"(\d+(?:\.\d+)?)\s*(d|days?|h|hrs?|hours?|m|mins?|minutes?|s|secs?|seconds?)\b"
DUR = r"((?:" + DUR_TOKEN + r"[\s,]*(?:and\s+)?)+)"


def read(paths, cap=2_000_000):
    out = []
    for p in paths:
        try:
            with open(p, "rb") as f:
                f.seek(0, 2); size = f.tell(); f.seek(max(0, size - cap))
                out.append(f.read().decode("utf-8", "replace"))
        except OSError:
            pass
    return "\n".join(out)


def clock(h, mi, ap):
    h = int(h) % 12 if ap else int(h)
    if ap and ap.lower().startswith("p"):
        h += 12
    return h, int(mi)


def parse_reset(text):
    """Latest statement wins. Returns an epoch or None."""
    found = []  # (position, epoch)
    # Codex: "try again at Sep 22nd, 2026 9:51 AM"   (local time)
    for m in re.finditer(r"(?:try again|available again|resets?)\s+(?:at|on)\s+([A-Za-z]{3})[a-z]*\.?\s+(\d{1,2})(?:st|nd|rd|th)?,?\s+(\d{4}),?\s+(?:at\s+)?(\d{1,2}):(\d{2})\s*([AaPp]\.?[Mm]\.?)?", text):
        mon = MONTHS.get(m.group(1).lower())
        if mon:
            h, mi = clock(m.group(4), m.group(5), m.group(6))
            try:
                found.append((m.start(), time.mktime((int(m.group(3)), mon, int(m.group(2)), h, mi, 0, 0, 0, -1))))
            except (ValueError, OverflowError):
                pass
    # Codex, same day: "try again at 4:32 PM"
    for m in re.finditer(r"(?:try again|available again|resets?)\s+at\s+(\d{1,2}):(\d{2})\s*([AaPp]\.?[Mm]\.?)?(?![\d:])", text):
        h, mi = clock(m.group(1), m.group(2), m.group(3))
        lt = time.localtime(NOW)
        t = time.mktime((lt.tm_year, lt.tm_mon, lt.tm_mday, h, mi, 0, 0, 0, -1))
        found.append((m.start(), t if t > NOW else t + 86400))
    # "try again in 3 days 5 hours 12 minutes" · OpenCode Go: "5-hour usage limit reached. Resets in 2h 13m"
    for m in re.finditer(r"(?:try again|retry(?:ing)?|resets?|available(?: again)?)\s+in\s+(?:about\s+|~\s*)?" + DUR, text, re.I):
        secs = sum(float(n) * UNIT[u[0].lower()] for n, u in re.findall(DUR_TOKEN, m.group(1), re.I))
        if secs > 0:
            found.append((m.start(), NOW + secs))
    if found:
        return max(found)[1]
    # a window reported as full, with its reset time (Codex error items / rate_limits objects)
    full = []
    for m in re.finditer(r'"used_percent"\s*:\s*(\d+(?:\.\d+)?)[^{}]*?"resets_at"\s*:\s*(\d{9,13})', text):
        if float(m.group(1)) >= 99.5:
            full.append(norm_epoch(m.group(2)))
    full = [e for e in full if e and e > NOW]
    if full:
        return max(full)
    m = re.search(r'"resets_at"\s*:\s*(\d{9,13})', text)
    if m and (norm_epoch(m.group(1)) or 0) > NOW:
        return norm_epoch(m.group(1))
    m = re.search(r"retry-after-ms[\"']?\s*[:=]\s*[\"']?(\d+)", text, re.I)
    if m:
        return NOW + int(m.group(1)) / 1000.0
    m = re.search(r"retry-after[\"']?\s*[:=]\s*[\"']?(\d+)\b", text, re.I)
    if m:
        return NOW + int(m.group(1))
    return None


def norm_epoch(v):
    try:
        v = float(v)
    except (TypeError, ValueError):
        return None
    return v / 1000.0 if v > 1e12 else v


def find_key(obj, key):
    if isinstance(obj, dict):
        if key in obj and isinstance(obj[key], dict):
            yield obj[key]
        for v in obj.values():
            yield from find_key(v, key)
    elif isinstance(obj, list):
        for v in obj:
            yield from find_key(v, key)


def iso_epoch(s):
    try:
        import datetime
        return datetime.datetime.fromisoformat(str(s).replace("Z", "+00:00")).timestamp()
    except Exception:
        return None


def codex_snapshot():
    """Newest rate_limits object with at least one real window, from the most recent Codex session files."""
    root = os.path.join(os.environ.get("CODEX_HOME") or os.path.expanduser("~/.codex"), "sessions")
    files = glob.glob(os.path.join(root, "**", "rollout-*.jsonl"), recursive=True)
    files.sort(key=lambda p: os.path.getmtime(p), reverse=True)
    best = None
    for p in files[:8]:
        text = read([p], cap=600_000)
        for line in reversed(text.splitlines()):
            if '"rate_limits"' not in line:
                continue
            try:
                obj = json.loads(line)
            except ValueError:
                continue
            ts = iso_epoch(obj.get("timestamp")) if isinstance(obj, dict) else None
            ts = ts or os.path.getmtime(p)
            for rl in find_key(obj, "rate_limits"):
                wins = []
                for name in ("primary", "secondary"):
                    w = rl.get(name)
                    if not isinstance(w, dict) or w.get("used_percent") is None:
                        continue
                    reset = norm_epoch(w.get("resets_at"))
                    if reset is None and w.get("resets_in_seconds") is not None:
                        reset = ts + float(w["resets_in_seconds"])
                    wins.append({"name": name, "used": float(w["used_percent"]), "minutes": w.get("window_minutes"), "reset": reset})
                if wins and (best is None or ts > best["ts"]):
                    best = {"ts": ts, "windows": wins, "plan": rl.get("plan_type")}
            if best and best["ts"] >= os.path.getmtime(p) - 1:
                break
        if best:
            break  # files are newest first; an older file cannot hold a newer snapshot
    return best


def dur(s):
    s = int(max(0, s)); d, s = divmod(s, 86400); h, s = divmod(s, 3600); m = s // 60
    return f"{d}d {h}h" if d else (f"{h}h {m:02d}m" if h else f"{m}m")


def window_name(w):
    mins = w.get("minutes")
    if not mins:
        return w["name"]
    mins = int(mins)
    return f"{mins // 1440}-day window" if mins >= 1440 else (f"{mins // 60}-hour window" if mins >= 60 else f"{mins}-min window")


def main(argv):
    cmd = argv[1] if len(argv) > 1 else ""
    if cmd == "reset":
        e = parse_reset(read(argv[2:]))
        if e and e > NOW:
            print(int(e))
    elif cmd == "codex-usage":
        snap = codex_snapshot()
        if "--since" in argv:  # `ai-limits clear` means "I know better than that snapshot" (credits bought, plan changed)
            try:
                if snap and snap["ts"] <= float(argv[argv.index("--since") + 1]):
                    snap = None
            except (IndexError, ValueError):
                pass
        if "--exhausted" in argv:
            if snap:
                full = [w["reset"] for w in snap["windows"] if w["used"] >= 99.5 and w["reset"] and w["reset"] > NOW]
                if full:
                    print(int(max(full)))
            return
        if not snap:
            print("codex: no usage snapshot found in ~/.codex/sessions (run one Codex turn first)"); return
        parts = []
        for w in snap["windows"]:
            s = f"{window_name(w)} {w['used']:.0f}% used"
            if w["reset"]:
                s += (f", resets {time.strftime('%a %H:%M', time.localtime(w['reset']))} (in {dur(w['reset'] - NOW)})"
                      if w["reset"] > NOW else ", window has reset since")
            parts.append(s)
        print("codex: " + " · ".join(parts) + f" — as of {dur(NOW - snap['ts'])} ago" + (f" (plan: {snap['plan']})" if snap.get("plan") else ""))
    elif cmd == "codex-last":
        last = ""
        for line in read(argv[2:], cap=20_000_000).splitlines():
            if '"agent_message"' not in line:
                continue
            try:
                item = json.loads(line).get("item") or {}
            except ValueError:
                continue
            if item.get("type") == "agent_message" and item.get("text"):
                last = item["text"]
        if last:
            print(last)
    else:
        sys.stderr.write(__doc__); sys.exit(64)


if __name__ == "__main__":
    try:
        main(sys.argv)
    except Exception:  # helpers must never break the caller
        sys.exit(0)
