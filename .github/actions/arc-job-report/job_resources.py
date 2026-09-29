#!/usr/bin/env python3
"""CPU/memory use of GitHub Actions jobs that ran on the ARC runners, with a size suggestion.

Usage:
  job-resources.py https://github.com/<org>/<repo>/actions/runs/<run-id>[/job/<job-id>] [--json]

Needs `gh` (authenticated) and either GRAFANA_TOKEN (a Grafana service-account token with read
access to the Prometheus datasource) or `gcx` (a context with that datasource).
A job's runner name (GitHub API `runner_name`) is its ARC pod name; metrics are scraped every 60 s,
so jobs shorter than ~2 minutes get only a sample or two.

Copied from monta-app/kube-manifests infra/arc/scripts/job-resources.py @ dd43b0172; the only
change is the GRAFANA_TOKEN query path in prom().
"""
import json
import math
import os
import re
import subprocess
import sys
import urllib.parse
import urllib.request
from datetime import datetime

DATASOURCE = "grafanacloud-prom"
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


def sh(*args):
    return subprocess.run(args, capture_output=True, text=True, check=True).stdout


def prom(expr, start, end, step=60):
    token = os.environ.get("GRAFANA_TOKEN")
    if token:
        query = urllib.parse.urlencode({"query": expr, "start": start, "end": end, "step": step})
        req = urllib.request.Request(f"{GRAFANA}/api/datasources/proxy/uid/{DATASOURCE}/api/v1/query_range?{query}",
                                     headers={"Authorization": f"Bearer {token}"})
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.load(resp)["data"]["result"]
    out = sh("gcx", "metrics", "query", "-d", DATASOURCE, expr,
             "--from", str(start), "--to", str(end), "--step", f"{step}s", "-o", "json")
    return json.loads(out)["data"]["result"]


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


def suggest(arch, peak_mem_gib, p95_cpu):
    need_mem, need_cpu = peak_mem_gib * 1.3, max(p95_cpu * 1.2, 1)
    for name, a, cpu, mem in CATALOG:
        if a == arch and mem >= need_mem and cpu >= need_cpu:
            return name
    return next((n for n, a, _, _ in reversed(CATALOG) if a == arch), None)


def analyse(job):
    pod, start, end = job["runner_name"], ts(job["started_at"]), ts(job["completed_at"])
    sel = f'cluster="internal", namespace="arc", pod="{pod}"'
    lo, hi = start - 60, end + 60
    cpu = values(prom(f'sum(rate(container_cpu_usage_seconds_total{{{sel}, container=~"runner|dind"}}[2m]))', lo, hi))
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
    res.update({
        "cpu_cores": {"avg": round(sum(cpu) / len(cpu), 2), "p95": round(p95, 2), "max": round(max(cpu), 2),
                      "request": max(req) if req else None},
        "memory_gib": {"peak": round(peak_mem, 2), "limit": round(max(lim) / 2**30, 1) if lim else None},
        "oom_kills": int(max(oom)) if oom else 0,
        "suggested_runner": suggest(res["node"]["arch"], peak_mem, p95),
    })
    notes = []
    if duration < 120:
        notes.append("short job: only a few 60 s samples, low confidence")
    if res["node"]["vcpu"] and p95 >= 0.85 * res["node"]["vcpu"]:
        notes.append("CPU-bound on this node: a larger size may make it faster")
    if res["oom_kills"]:
        notes.append("OOM-killed: needs more memory")
    if notes:
        res["note"] = "; ".join(notes)
    return res


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if not args:
        sys.exit(__doc__)
    results = [analyse(j) for j in jobs_for(args[0])
               if j.get("runner_name") and ARC_RUNNER.match(j["runner_name"]) and j.get("completed_at")]
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
            c, m = r["cpu_cores"], r["memory_gib"]
            print(f"  cpu     avg {c['avg']}  p95 {c['p95']}  max {c['max']} cores   (request {c['request']})\n"
                  f"  memory  peak {m['peak']} GiB of {m['limit']} GiB limit   OOM kills: {r['oom_kills']}\n"
                  f"  suggest {r['suggested_runner']}")
        if r.get("note"):
            print(f"  note    {r['note']}")
        print(f"  graphs  {r['dashboard']}")


if __name__ == "__main__":
    main()
