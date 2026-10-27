#!/usr/bin/env python3
"""ai-night run receipts (0.22.0). Standard library only.

  _receipts.py write <dir> <out.json> <repo> <handoff> <n> <outcome> <sec> <before> <after>
      One receipt per spec run: <dir>/<YYYY-MM-DD>/<repo>-<HHMMSS>-<n>.json, then that night's SUMMARY.md again.
  _receipts.py report <dir> [--days N]
      Accepted (the run's branch tip is in its base), rejected (not in it after 7 days), pending (younger).
      A squash merge drops the tip from the base, so it reads as rejected: merge night branches with a merge commit.
  _receipts.py backfill <dir> <night.log> <night-output-dir> <repos-root>
      Receipts for the runs already in night.log, from the saved outputs. Skips a run that has a receipt.

A receipt holds no prompt text and no secrets: counts, cost, statuses, the branch and its tip.
"""
import datetime as dt
import glob
import json
import os
import re
import subprocess
import sys

OPEN = ("approved", "building")
REJECT_AFTER_DAYS = 7


def git(repo, *args):
    try:
        r = subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True, timeout=30)
        return r.stdout.strip() if r.returncode == 0 else None
    except Exception:
        return None


def branch_commits(repo, tip, base):
    """Commits of the branch. Unmerged: base..tip. Merged: from the base's first parent at the merge commit to the tip."""
    if subprocess.run(["git", "-C", repo, "merge-base", "--is-ancestor", tip, base], capture_output=True).returncode != 0:
        return git(repo, "rev-list", "--count", f"{base}..{tip}")
    line = git(repo, "rev-list", "--first-parent", "--ancestry-path", f"{tip}..{base}")
    if not line:  # fast-forward or the base is the tip: no merge commit to measure from
        return None
    merge = line.split()[-1]
    return git(repo, "rev-list", "--count", f"{merge}^1..{tip}")


def handoff_specs(path):
    """[(spec name, branch, base)] in file order, one per `Status:` line."""
    try:
        text = open(path, encoding="utf-8").read()
    except OSError:
        return []
    specs, name, branch, base = [], None, None, None
    for line in text.splitlines():
        m = re.match(r"^##\s+(?:\d+\.\s*)?(.+?)\s*$", line)
        if m:
            name, branch, base = m.group(1), None, None
            continue
        m = re.match(r"^-\s*Branch:\s*`([^`]+)`(?:,\s*base\s*`([^`]+)`)?", line)
        if m:
            branch, base = m.group(1), m.group(2)
            continue
        if re.match(r"^Status:\s*[a-z]+", line):
            specs.append((name, branch, base))
    return specs


def changed_index(before, after):
    b, a = before.split(), after.split()
    for i, (x, y) in enumerate(zip(b, a)):
        if x != y:
            return i
    return next((i for i, x in enumerate(a) if x in OPEN), None) if a else None


def load_json(path):
    try:
        return json.load(open(path, encoding="utf-8"))
    except Exception:
        return {}


def receipt(out_json, repo, handoff, n, outcome, sec, before, after, when):
    d = load_json(out_json)
    u = d.get("usage") or {}
    specs = handoff_specs(handoff)
    i = changed_index(before, after)
    name, branch, base = specs[i] if i is not None and i < len(specs) else (None, None, None)
    base = base or "main"
    tip = git(repo, "rev-parse", "--verify", "-q", branch) if branch else None
    commits = branch_commits(repo, tip, base) if tip else None
    after_list = after.split()
    return {
        "date": when.strftime("%Y-%m-%d"), "ended": when.strftime("%Y-%m-%dT%H:%M:%S"),
        "repo": os.path.basename(repo), "repo_path": repo, "handoff": os.path.relpath(handoff, repo),
        "run": n, "outcome": outcome, "spec": name,
        "status_before": before.split()[i] if i is not None and i < len(before.split()) else None,
        "status_after": after_list[i] if i is not None and i < len(after_list) else None,
        "branch": branch, "base": base, "tip": tip, "commits": int(commits) if commits else None,
        "seconds": int(sec) if str(sec).isdigit() else None,
        "cost_usd": d.get("total_cost_usd"), "turns": d.get("num_turns"), "session": d.get("session_id"),
        "tokens": {k: u.get(k) for k in ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens", "output_tokens")},
        "models": sorted((d.get("modelUsage") or {}).keys()),
    }


def save(rdir, r, when):
    day = os.path.join(rdir, r["date"])
    os.makedirs(day, exist_ok=True)
    path = os.path.join(day, f"{r['repo']}-{when.strftime('%H%M%S')}-{r['run']}.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(r, f, indent=2)
        f.write("\n")
    summary(day)
    return path


def money(x):
    return f"${x:.2f}" if isinstance(x, (int, float)) else "?"


def summary(day):
    rows = [load_json(p) for p in sorted(glob.glob(os.path.join(day, "*.json")))]
    cost = sum(r.get("cost_usd") or 0 for r in rows)
    secs = sum(r.get("seconds") or 0 for r in rows)
    lines = [f"# ai-night receipts, {os.path.basename(day)}", "",
             f"{len(rows)} spec runs, {money(cost)} API-equivalent, {secs // 3600} h {secs % 3600 // 60:02d} min.", "",
             "| Repo | Spec | Outcome | Status | Branch | Commits | Time | Cost |", "|---|---|---|---|---|---|---|---|"]
    for r in rows:
        lines.append("| {} | {} | {} | {} → {} | `{}` | {} | {} min | {} |".format(
            r.get("repo"), r.get("spec") or "?", r.get("outcome"), r.get("status_before") or "?", r.get("status_after") or "?",
            r.get("branch") or "?", r.get("commits") if r.get("commits") is not None else "?",
            (r.get("seconds") or 0) // 60, money(r.get("cost_usd"))))
    lines += ["", "Accepted or rejected: `ai-night --receipts`."]
    with open(os.path.join(day, "SUMMARY.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


def verdict(r, today):
    repo, tip, base = r.get("repo_path"), r.get("tip"), r.get("base") or "main"
    if not tip:
        branch = r.get("branch")
        tip = git(repo, "rev-parse", "--verify", "-q", branch) if (repo and branch) else None
    if r.get("commits") == 0:
        return "rejected" if (today - dt.date.fromisoformat(r["date"])).days >= REJECT_AFTER_DAYS else "pending"
    if tip and repo and subprocess.run(["git", "-C", repo, "merge-base", "--is-ancestor", tip, base],
                                       capture_output=True).returncode == 0:
        return "accepted"
    age = (today - dt.date.fromisoformat(r["date"])).days
    return "rejected" if age >= REJECT_AFTER_DAYS else "pending"


def report(rdir, days):
    today = dt.date.today()
    since = today - dt.timedelta(days=days)
    rows = []
    for p in sorted(glob.glob(os.path.join(rdir, "*", "*.json"))):
        r = load_json(p)
        if r.get("date") and dt.date.fromisoformat(r["date"]) >= since:
            rows.append(r)
    if not rows:
        print(f"receipts: no run in the last {days} days ({rdir})")
        return
    counts = {"accepted": 0, "rejected": 0, "pending": 0, "failed": 0, "retried": 0}
    cost = 0.0
    for r in rows:
        o = r.get("outcome")
        v = verdict(r, today) if o == "ok" else ("retried" if o == "limit" else "failed")
        counts[v] += 1
        cost += r.get("cost_usd") or 0
        print(f"{r['date']}  {r.get('repo')}  {r.get('spec') or '?'}  {o}  {v}  {money(r.get('cost_usd'))}")
    per = money(cost / counts["accepted"]) if counts["accepted"] else "none accepted"
    print(f"receipts ({days} days): {len(rows)} runs, {counts['accepted']} accepted, {counts['rejected']} rejected, "
          f"{counts['pending']} pending, {counts['failed']} failed (no progress or error), {counts['retried']} hit a limit, "
          f"{money(cost)}, {per} per accepted spec")


def find_repo(root, name):
    for p in [os.path.join(root, name)] + glob.glob(os.path.join(root, "*", name)):
        if os.path.isdir(os.path.join(p, ".git")):
            return p
    return None


def backfill(rdir, log, nd, root):
    done = {(r.get("session")) for r in (load_json(p) for p in glob.glob(os.path.join(rdir, "*", "*.json")))}
    if not os.path.isfile(log):
        print(f"backfill: no night log at {log}")
        return
    prev, made = {}, 0
    for line in open(log, encoding="utf-8"):
        parts = line.rstrip("\n").split("\t")
        if len(parts) < 6 or parts[3] == "-" or parts[4] in ("done", "stopped"):
            continue
        ts, name, rel, n, outcome, detail = parts[:6]
        repo = find_repo(root, name)
        if not repo:
            continue
        when = dt.datetime.fromisoformat(ts)
        m = re.search(r"(?:^|; )((?:[a-z]+ )*[a-z]+) ?; session", detail)
        key = (name, rel)
        after = m.group(1) if m else (prev.get(key) or "")
        before = prev.get(key) or " ".join(
            ("approved" if i == 0 else s) for i, s in enumerate(after.split()))  # first run: assume spec 1 changed
        prev[key] = after or before
        outs = [p for p in sorted(glob.glob(os.path.join(nd, f"*-{name}-{n}.json")))
                if dt.datetime.strptime(os.path.basename(p)[:15], "%Y%m%d-%H%M%S") <= when]
        if not outs:
            continue
        sec = (re.match(r"(\d+)s", detail) or [None, ""])[1]
        r = receipt(outs[-1], repo, os.path.join(repo, rel), int(n), outcome, sec, before, after, when)
        if r.get("session") in done:
            continue
        save(rdir, r, when)
        made += 1
    print(f"backfill: {made} receipts written to {rdir}")


def main(a):
    if len(a) >= 10 and a[0] == "write":
        rdir, out, repo, handoff, n, outcome, sec, before, after = a[1:10]
        when = dt.datetime.now()
        print(save(rdir, receipt(out, repo, handoff, int(n), outcome, sec, before, after, when), when))
    elif len(a) >= 2 and a[0] == "report":
        days = int(a[a.index("--days") + 1]) if "--days" in a else 30
        report(a[1], days)
    elif len(a) == 5 and a[0] == "backfill":
        backfill(*a[1:5])
    else:
        print(__doc__, file=sys.stderr)
        return 64
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
