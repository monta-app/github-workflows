#!/usr/bin/env python3
"""Post or update a PR comment with the CPU/memory use of a workflow run's ARC jobs.

Usage:
  arc_job_report.py https://github.com/<org>/<repo>/actions/runs/<run-id> [--dry-run]

Needs `gh` authenticated (GH_TOKEN) and GRAFANA_TOKEN, or `gcx` for local runs; see job_resources.py.

The PR gets one comment: the latest run's per-job table, plus a history row per run so
speed changes can be traced to commits. Only a bot-authored comment is updated, so run it
locally with --dry-run, which prints the comment instead of posting it.
"""
import json
import re
import subprocess
import sys
from datetime import datetime

from job_resources import ARC_RUNNER, analyse, jobs_for, sh

MARKER = "<!-- arc-job-report -->"
HISTORY = re.compile(r"<!-- history (\[.*?\]) -->", re.S)
SHARD = re.compile(r"^(.*) - shard (\d+)$")
RESULT = {"success": "✅", "failure": "❌"}
# ponytail: keeps the last 50 runs so the comment stays far below GitHub's 65,536-character limit
MAX_HISTORY = 50


def seconds(start, end):
    return int((datetime.fromisoformat(end.replace("Z", "+00:00"))
                - datetime.fromisoformat(start.replace("Z", "+00:00"))).total_seconds())


def minutes(s):
    return f"{s}s" if s < 60 else f"{s // 60}m {s % 60:02d}s"


def delta(now, before):
    d = now - before
    return "±0s" if d == 0 else f"{'▲' if d > 0 else '▼'} {minutes(abs(d))}"


def api(method, path, body=None):
    out = subprocess.run(["gh", "api", "-X", method, path, "--input", "-"], input=json.dumps(body or {}),
                         capture_output=True, text=True, check=True).stdout
    return json.loads(out) if out else None


def size(runner):
    return re.sub(r"^arc-(arm64-)?", "", re.sub(r"-[a-z0-9]+-runner-[a-z0-9]+$", "", runner))


def rank(runner):
    return tuple(int(n) for n in re.findall(r"(\d+)(?:cpu|gb)", runner))


def name(r):
    return re.sub(r" *[(].*[)]$", "", r["job"])


def job_rows(results):
    groups = {}
    for r in results:
        shard = SHARD.match(name(r))
        groups.setdefault((shard.group(1), True) if shard else (name(r), False), []).append(r)
    rows = []
    for (label, sharded), jobs in sorted(groups.items()):
        slow = max(jobs, key=lambda r: r["duration_s"])
        if not sharded:
            rows.append(f"| [{label}]({slow['dashboard']}) | {minutes(slow['duration_s'])} |")
            continue
        fast = min(jobs, key=lambda r: r["duration_s"])
        number = {id(r): SHARD.match(name(r)).group(2) for r in jobs}
        links = " ".join(f"**[{number[id(r)]}]({r['dashboard']})**" if r is slow else f"[{number[id(r)]}]({r['dashboard']})"
                         for r in sorted(jobs, key=lambda r: int(number[id(r)])))
        time = minutes(slow["duration_s"]) if fast is slow else f"{minutes(fast['duration_s'])} – {minutes(slow['duration_s'])}"
        rows.append(f"| {label} · shards {links} | {time} |")
    return rows


def change(r):
    if r["duration_s"] < 120:
        return None
    runner, suggested = size(r["runner"]), size(r.get("suggested_runner") or r["runner"])
    return None if suggested == runner else (runner, suggested)


def suggestion_row(r):
    runner, suggested = change(r)
    arrow = "⬇️" if rank(suggested) < rank(runner) else "⬆️"
    return (f"| [{name(r)}]({r['dashboard']}) | {arrow} {runner} → {suggested} | {r['cpu_cores']['max']:.1f} | "
            f"{r['memory_gib']['peak']:.1f} GiB |")


def history_row(h, previous):
    wall = minutes(h["wall"]) + (" (re-run)" if h["attempt"] > 1 else "")
    slowest = f"{h['slowest']} ({minutes(h['slowest_s'])})" if h["slowest"] else "–"
    return (f"| [#{h['run']}]({h['url']}) | `{h['sha']}` | {RESULT.get(h['conclusion'], '⚠️')} | {wall} | "
            f"{delta(h['wall'], previous['wall']) if previous else '–'} | {slowest} |")


def render(run, results, previous_body):
    match = HISTORY.search(previous_body or "")
    history = {h["run"]: h for h in json.loads(match.group(1))} if match else {}
    slowest = max(results, key=lambda r: r["duration_s"], default=None)
    current = history[run["run_number"]] = {
        "run": run["run_number"], "url": run["html_url"], "sha": run["head_sha"][:7],
        "conclusion": run["conclusion"], "attempt": run.get("run_attempt", 1),
        "wall": seconds(run["run_started_at"], run["updated_at"]),
        "slowest": name(slowest) if slowest else None, "slowest_s": slowest["duration_s"] if slowest else None,
    }
    runs = [history[n] for n in sorted(history)][-MAX_HISTORY:]
    previous = {h["run"]: p for p, h in zip(runs, runs[1:])}
    before = previous.get(current["run"])
    changed = [r for r in sorted(results, key=lambda r: r["job"]) if change(r)]
    summary = (f"{RESULT.get(current['conclusion'], '⚠️')} <b>{minutes(current['wall'])}</b>"
               + (f" ({delta(current['wall'], before['wall'])} vs previous run)" if before else "")
               + f" · 🏃 ARC runners · <a href=\"{current['url']}\">run #{current['run']}</a> · {current['sha']}"
               + (f" · 💡 {len(changed)} runner change{'s' if len(changed) != 1 else ''}" if changed else ""))
    return "\n".join([
        MARKER,
        f"<details><summary>{summary}</summary>",
        "",
        "Job names and shard numbers link to their CPU and memory graphs; the slowest shard is bold.",
        "",
        "| Job | Time |",
        "|---|---|",
        *job_rows(results),
        "",
        *(["💡 **Suggested runner changes.** Memory is the exact peak; CPU is the max of 60 s averages, so "
           "trial before downsizing on it. Jobs under 2 min have too few samples and are left out.",
           "",
           "| Job | Change | CPU | Memory |",
           "|---|---|---|---|",
           *map(suggestion_row, changed),
           ""] if changed else []),
        f"<!-- history {json.dumps(runs)} -->",
        "| Run | Commit | Result | Wall time | Δ | Slowest job |",
        "|---|---|---|---|---|---|",
        *[history_row(h, previous.get(h["run"])) for h in runs],
        "",
        "</details>",
    ])


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if not args:
        sys.exit(__doc__)
    match = re.search(r"github\.com/([^/]+/[^/]+)/actions/runs/(\d+)", args[0])
    if not match:
        sys.exit(f"not a GitHub Actions run URL: {args[0]!r}")
    repo, run_id = match.groups()
    run = json.loads(sh("gh", "api", f"repos/{repo}/actions/runs/{run_id}"))
    prs = run["pull_requests"] or json.loads(sh("gh", "api", f"repos/{repo}/commits/{run['head_sha']}/pulls"))
    if not prs:
        sys.exit(f"no pull request found for run {run_id}")
    pr = prs[0]["number"]
    results = [analyse(j) for j in jobs_for(args[0])
               if j.get("runner_name") and ARC_RUNNER.match(j["runner_name"]) and j.get("completed_at")]
    comments = json.loads(sh("gh", "api", "--paginate", "--slurp", f"repos/{repo}/issues/{pr}/comments"))
    existing = next((c for page in reversed(comments) for c in reversed(page)
                     if MARKER in c["body"] and c["user"]["type"] == "Bot"), None)
    body = render(run, results, existing and existing["body"])
    if "--dry-run" in sys.argv:
        print(body)
    elif existing:
        api("PATCH", f"repos/{repo}/issues/comments/{existing['id']}", {"body": body})
    else:
        api("POST", f"repos/{repo}/issues/{pr}/comments", {"body": body})


if __name__ == "__main__":
    main()
