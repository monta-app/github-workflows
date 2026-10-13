#!/usr/bin/env python3
"""CPU/memory use of GitHub Actions jobs that ran on the ARC runners, with a size suggestion.

Usage:
  job-resources.py https://github.com/<org>/<repo>/actions/runs/<run-id>[/job/<job-id>] [--json]

Needs `gh` (authenticated) and either GRAFANA_TOKEN (a Grafana service-account token with read
access to the Prometheus datasource) or `gcx` (a context with that datasource).
A job's runner name (GitHub API `runner_name`) is its ARC pod name; metrics are scraped every 15 s.
A job's history across runs comes from the arc:job_* recording rules (monta-app/terraform,
global/grafana/teams/sre/alerts_arc.tf).
"""
import json
import math
import os
import re
import statistics
import subprocess
import sys
import urllib.parse
import urllib.request
from datetime import datetime

DATASOURCE = "ffzoywkuhm5tsd"  # mimir-internal
GRAFANA = "https://montaapp.grafana.net"
ARC_RUNNER = re.compile(r"^(self-hosted|arc)-")
# (name, arch, vCPU, memory GiB) -- keep in sync with infra/arc/README.md
CATALOG = [
    ("arc-arm64-2cpu-4gb", "arm64", 2, 4),
    ("arc-arm64-4cpu-12gb", "arm64", 4, 12),
    ("arc-arm64-8cpu-24gb", "arm64", 8, 24),
    ("arc-arm64-16cpu-48gb", "arm64", 16, 48),
    ("arc-x64-4cpu-12gb", "amd64", 4, 12),
    ("arc-x64-8cpu-24gb", "amd64", 8, 24),
]
JOB_MEMORY = "arc:job_memory_working_set_bytes:max1m"
JOB_CPU = "arc:job_cpu_usage_cores:rate1m"
WINDOW = "7d"
MIN_RUNS = 5
MEMORY_HEADROOM = 1.3
CPU_BOUND = 0.85


def sh(*args):
    return subprocess.run(args, capture_output=True, text=True, check=True).stdout


def get(api, **params):
    path = f"/api/datasources/proxy/uid/{DATASOURCE}/api/v1/{api}?{urllib.parse.urlencode(params)}"
    token = os.environ.get("GRAFANA_TOKEN")
    if token:
        req = urllib.request.Request(GRAFANA + path, headers={"Authorization": f"Bearer {token}"})
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.load(resp)["data"]["result"]
    return json.loads(sh("gcx", "api", path))["data"]["result"]


def prom(expr, start, end, step=15):
    return get("query_range", query=expr, start=start, end=end, step=step)


def label(value):
    return value.replace("\\", "\\\\").replace('"', '\\"')


def history(repo, names):
    if not names:
        return {}
    regex = "|".join(re.sub(r"([.*+?^${}()|\[\]\\])", r"\\\1", n) for n in sorted(set(names)))
    sel = f'repository="{label(repo)}", job_name=~"{label(regex)}"'

    def by_job(expr):
        return {r["metric"]["job_name"]: float(r["value"][1]) for r in get("query", query=expr)}

    mem = by_job(f"max by (job_name) (max_over_time({JOB_MEMORY}{{{sel}}}[{WINDOW}]))")
    cpu_p50 = by_job(f"quantile by (job_name) (0.5, quantile_over_time(0.5, {JOB_CPU}{{{sel}}}[{WINDOW}]))")
    cpu_peak = by_job(f"max by (job_name) (max_over_time({JOB_CPU}{{{sel}}}[{WINDOW}]))")
    runs = by_job(f"count by (job_name) (count by (job_name, workflow_run_id) (count_over_time({JOB_MEMORY}{{{sel}}}[{WINDOW}])))")
    return {n: {"runs": int(runs.get(n, 0)), "peak_mem_gib": mem[n] / 2**30,
                "cpu_p50": cpu_p50.get(n), "cpu_peak": cpu_peak.get(n)} for n in mem}


def values(result):
    return [float(v[1]) for r in result for v in r.get("values", [])]


def last_labels(result):
    return result[0]["metric"] if result else {}


def ts(iso):
    return int(datetime.fromisoformat(iso.replace("Z", "+00:00")).timestamp())


def jobs_for(url):
    m = re.search(r"github\.com/([^/]+/[^/]+)/actions/runs/(\d+)(?:/job/(\d+))?", url)
    if not m:
        sys.exit(f"not a GitHub Actions run/job URL: {url}")
    repo, run, job = m.groups()
    if job:
        return [json.loads(sh("gh", "api", f"repos/{repo}/actions/jobs/{job}"))]
    out = sh("gh", "api", "--paginate", f"repos/{repo}/actions/runs/{run}/jobs", "--jq", ".jobs[] | @json")
    return [json.loads(line) for line in out.splitlines() if line]


def suggest(runner, arch, peak_mem_gib, cpu_p50, cpu_peak, runs, oom):
    sizes = [c for c in CATALOG if c[1] == arch]
    now = next((c for c in sizes if runner.startswith(c[0] + "-")), None)
    if not now:
        return None
    i = sizes.index(now)
    fits = [c for c in sizes if c[3] >= peak_mem_gib * MEMORY_HEADROOM]
    need = sizes.index(fits[0]) if fits else len(sizes) - 1
    if oom:
        need = max(need, i + 1)
    if need > i:
        return sizes[min(need, len(sizes) - 1)][0], "memory"
    if cpu_p50 >= CPU_BOUND * now[2] and i + 1 < len(sizes):
        return sizes[i + 1][0], "faster"
    smaller = next((c for c in fits if c[2] >= cpu_p50), now)
    if runs < MIN_RUNS or sizes.index(smaller) >= i:
        return None
    return smaller[0], "fits" if smaller[2] >= cpu_peak else "trial"


def analyse(job, hist):
    pod, start, end = job["runner_name"], ts(job["started_at"]), ts(job["completed_at"])
    sel = f'cluster="internal", namespace="arc", pod="{pod}"'
    lo, hi = start - 60, end + 60
    cpu = values(prom(f'sum(rate(container_cpu_usage_seconds_total{{{sel}, container=~"runner|dind"}}[1m]))', lo, hi))
    mem = values(prom(f'sum(container_memory_working_set_bytes{{{sel}, container=~"runner|dind"}})', lo, hi))
    req = values(prom(f'max(kube_pod_container_resource_requests{{{sel}, container="runner", resource="cpu"}})', lo, hi))
    lim = values(prom(f'max(kube_pod_container_resource_limits{{{sel}, container="runner", resource="memory"}})', lo, hi))
    oom = values(prom(f'sum(increase(container_oom_events_total{{{sel}}}[{max(end - start, 60)}s]))', end, end))
    node = last_labels(prom(
        f'max by (node) (kube_pod_info{{{sel}}}) * on(node) group_left(label_node_kubernetes_io_instance_type, '
        f'label_karpenter_sh_capacity_type, label_kubernetes_io_arch) max by (node, label_node_kubernetes_io_instance_type, '
        f'label_karpenter_sh_capacity_type, label_kubernetes_io_arch) (kube_node_labels{{cluster="internal"}})', lo, hi))
    vcpu = values(prom(f'max(kube_node_status_capacity{{cluster="internal", node="{node.get("node", "")}", resource="cpu"}})', lo, hi))
    duration = end - start
    res = {"job": job["name"], "url": job["html_url"], "conclusion": job.get("conclusion"),
           "runner": pod, "duration_s": duration,
           "node": {"name": node.get("node"), "instance_type": node.get("label_node_kubernetes_io_instance_type"),
                    "capacity": node.get("label_karpenter_sh_capacity_type"), "arch": node.get("label_kubernetes_io_arch"),
                    "vcpu": int(max(vcpu)) if vcpu else None},
           "dashboard": f"{GRAFANA}/d/arc-job-resources?var-pod={pod}&from={(start - 60) * 1000}&to={(end + 60) * 1000}"}
    if not cpu or not mem:
        res["note"] = "no metrics (pod not scraped yet, or metrics already expired)"
        return res
    cpu_sorted = sorted(cpu)
    p95 = cpu_sorted[min(len(cpu_sorted) - 1, math.ceil(0.95 * len(cpu_sorted)) - 1)]
    peak_mem = max(mem) / 2**30
    h = hist.get(job["name"], {})
    runs = h.get("runs", 0)
    week = {"runs": runs, "peak_mem_gib": round(max(peak_mem, h.get("peak_mem_gib", 0)), 2),
            "cpu_p50": round(h["cpu_p50"] if runs >= MIN_RUNS and h.get("cpu_p50") is not None
                             else statistics.median(cpu), 2),
            "cpu_peak": round(max(max(cpu), h.get("cpu_peak") or 0), 2)}
    res.update({
        "cpu_cores": {"avg": round(sum(cpu) / len(cpu), 2), "p95": round(p95, 2), "max": round(max(cpu), 2),
                      "request": max(req) if req else None},
        "memory_gib": {"peak": round(peak_mem, 2), "limit": round(max(lim) / 2**30, 1) if lim else None},
        "oom_kills": int(max(oom)) if oom else 0,
        "history": week,
    })
    res["suggested_runner"], res["reason"] = suggest(
        pod, res["node"]["arch"], week["peak_mem_gib"], week["cpu_p50"], week["cpu_peak"], runs,
        res["oom_kills"]) or (None, None)
    notes = []
    if duration < 120:
        notes.append("short job: few samples, low confidence")
    if res["node"]["vcpu"] and p95 >= 0.85 * res["node"]["vcpu"]:
        notes.append("CPU-bound on this node: a larger size may make it faster")
    if res["oom_kills"]:
        notes.append("OOM-killed: needs more memory")
    if notes:
        res["note"] = "; ".join(notes)
    return res


def analyse_run(url):
    jobs = [j for j in jobs_for(url)
            if j.get("runner_name") and ARC_RUNNER.match(j["runner_name"]) and j.get("completed_at")]
    hist = history(re.search(r"github\.com/([^/]+/[^/]+)/", url).group(1), [j["name"] for j in jobs])
    return [analyse(j, hist) for j in jobs]


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if not args:
        sys.exit(__doc__)
    results = analyse_run(args[0])
    if "--json" in sys.argv:
        print(json.dumps(results, indent=2))
        return
    if not results:
        print("No completed jobs on ARC runners in that run.")
    for r in results:
        n = r["node"]
        print(f"\n{r['job']}  ({r['duration_s']}s, {r['conclusion']})\n  runner  {r['runner']}\n"
              f"  node    {n['instance_type']} {n['capacity']} ({n['vcpu']} vCPU)")
        if "cpu_cores" in r:
            c, m, h = r["cpu_cores"], r["memory_gib"], r["history"]
            print(f"  cpu     avg {c['avg']}  p95 {c['p95']}  max {c['max']} cores   (request {c['request']})\n"
                  f"  memory  peak {m['peak']} GiB of {m['limit']} GiB limit   OOM kills: {r['oom_kills']}\n"
                  f"  {WINDOW}      {h['runs']} runs, peak memory {h['peak_mem_gib']} GiB, "
                  f"CPU median {h['cpu_p50']} peak {h['cpu_peak']} cores\n"
                  f"  suggest {r['suggested_runner'] or 'keep'} {r['reason'] or ''}")
        if r.get("note"):
            print(f"  note    {r['note']}")
        print(f"  graphs  {r['dashboard']}")


if __name__ == "__main__":
    main()
