# ARC Job Report

Keeps **one comment per PR** that shows how each job of a workflow run used its
self-hosted ARC runner, which jobs would fit a different runner size, and how the
run's wall time changes from commit to commit.

Collapsed, the comment is a single line:

> ▶ ✅ **4m 33s** (▲ 18s vs previous run) · 🏃 ARC runners · [run #6228](#) · 315e3c4 · 💡 2 runner changes

Expanded, it has:

- **Jobs:** each job's duration, with the job name linking to its pod on the
  [ARC Job Resources dashboard](https://montaapp.grafana.net/d/arc-job-resources).
  Sharded jobs (`<name> - shard N`) are merged into one row with the time range
  and a link per shard number; the slowest shard is bold.
- **Suggested runner changes:** only jobs where another catalog size would fit,
  marked ⬇️ (smaller) or ⬆️ (bigger), with peak memory and CPU. Left out
  entirely when every runner fits.
- **Run history:** one row per run (commit, ✅/❌, wall time, change vs the
  previous run, slowest job), so speed changes can be traced to commits. The
  history is stored as JSON in a hidden HTML comment and re-rendered on every
  run, keeping the last 50 runs.

The comment is edited in place on every run. Only a bot-authored comment is
updated, so a comment someone posted by running the script locally is left alone.

## Usage

Add a workflow that runs after the PR workflow completes. `workflow_run` runs from
the default branch, so the Grafana token is never exposed to code from the PR.

```yaml
name: ARC Job Report

on:
  workflow_run:
    workflows: [ "Pull Request Workflow" ]
    types: [ completed ]

permissions:
  actions: read
  pull-requests: write

jobs:
  report:
    if: github.event.workflow_run.event == 'pull_request' && github.event.workflow_run.conclusion != 'cancelled'
    runs-on: arc-arm64-2cpu-4gb
    timeout-minutes: 10
    steps:
      - uses: monta-app/github-workflows/.github/actions/arc-job-report@main
        with:
          github-token: ${{ github.token }}
          grafana-token: ${{ secrets.GRAFANA_CLOUD_TOKEN }}
```

No checkout is needed: the action ships its own scripts. Jobs that did not run on
an ARC runner (`arc-*` / `self-hosted-*`) are skipped.

| Input | Required | Description |
|---|---|---|
| `github-token` | yes | Reads the run's jobs and writes the comment. Needs `actions: read` and `pull-requests: write`. |
| `grafana-token` | yes | Grafana service-account token that can read the `grafanacloud-prom` datasource. |
| `run-url` | no | Run to report on. Defaults to the run that triggered the `workflow_run` event. |

## How to read the numbers

Metrics come from cAdvisor and kube-state-metrics, scraped every **60 s**.

- **Peak memory is reliable.** It is the highest working-set sample over the job.
- **CPU is not, for short jobs.** It is the highest 60 s average, so short bursts
  are averaged away. In service-ocpi, the CPU-based rule suggested 4 vCPU for the
  integration shards, but a trial run made every shard 17–97 s slower. Trial a
  smaller runner before moving to it.
- **Jobs under 2 minutes are left out of the suggestions.** They get too few
  samples. Jobs under a minute have none at all (CPU needs two samples), so they
  show `–`. There is no point waiting for them: a runner pod's samples stop once
  its job ends and the pod is deleted.

The suggested size is the smallest catalog runner with memory ≥ 1.3 × peak and
vCPU ≥ 1.2 × the CPU p95.

## Files

- `arc_job_report.py` — builds and posts the comment.
- `job_resources.py` — the per-job analysis. It is `infra/arc/scripts/job-resources.py`
  from monta-app/kube-manifests, plus a `GRAFANA_TOKEN` path that queries Prometheus
  through Grafana's datasource proxy instead of `gcx`. Keep the two in sync.
- `test_arc_job_report.py` — unit tests for the comment rendering:
  `python3 -m unittest discover -s .github/actions/arc-job-report -p 'test_*.py'`

## Running locally

With `gh` and a `gcx` context that can read the datasource (no `GRAFANA_TOKEN`
needed), print the comment for any run without posting it:

```bash
python3 .github/actions/arc-job-report/arc_job_report.py \
  https://github.com/monta-app/service-ocpi/actions/runs/36544901752 --dry-run
```
