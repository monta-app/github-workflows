# ARC Job Report

Keeps **one comment per PR** that shows how each job of a workflow run used its
self-hosted ARC runner, which jobs would fit a different runner size, and how the
run's wall time changes from commit to commit. Each reported workflow gets its own
section in that comment, and a run only updates its own workflow's section.

Collapsed, each section is a single line:

> ▶ Unit tests · ✅ **4m 33s** (▲ 18s vs previous run) · 🏃 ARC runners · [run #6228](#) · 315e3c4 · 💡 2 runner changes

Expanded, a section has:

- **Jobs:** each job's duration, with the job name linking to its pod on the
  [ARC Job Resources dashboard](https://montaapp.grafana.net/d/arc-job-resources).
  Sharded jobs (`<name> - shard N`, `<name> (shard N)` or `<name> (shard-N)`) are
  merged into one row with the time range and a link per shard number; the slowest shard is bold.
- **Suggested runner changes:** only jobs where another catalog size is
  suggested, marked ⬇️ (smaller) or ⬆️ (bigger) with the reason, the job's peak
  memory, median and peak CPU and number of runs over the last 7 days; the job
  name links to its dashboard. Shards with the same change share one row, with
  the highest memory and CPU and the fewest runs among them. Left out entirely
  when every runner is right.
- **Run history:** one row per run (commit, ✅/❌, wall time, change vs the
  previous run, slowest job), so speed changes can be traced to commits. The
  history is stored as JSON in a hidden HTML comment and re-rendered on every
  run, keeping the last 50 runs, split evenly between the sections.

The comment is edited in place on every run. Only a bot-authored comment is
updated, so a comment someone posted by running the script locally is left alone.
A comment from before sections existed is adopted as the reporting workflow's
section, history included.

## Usage

Add a workflow that runs after the PR workflow completes. The report then sees
every job finished and the run's final wall time, and it adds no job or check to
the PR workflow itself. `workflow_run` workflows only run from the default branch,
so the comments start once this workflow is on `main`.

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

To report several workflows, list them all in `workflows:`; they share the PR's one
comment. If they run on `push` rather than `pull_request` (as in monta-app/server),
drop the `event == 'pull_request'` condition: the report finds the PR from the
commit, and a run whose commit has no PR is skipped without failing.

| Input | Required | Description |
|---|---|---|
| `github-token` | yes | Reads the run's jobs and writes the comment. Needs `actions: read` and `pull-requests: write`. |
| `grafana-token` | yes | Grafana service-account token that can read the `mimir-internal` Prometheus datasource. |
| `run-url` | no | Run to report on. Defaults to the run that triggered the `workflow_run` event. |

## How to read the numbers

Metrics come from cAdvisor and kube-state-metrics in `mimir-internal`, scraped every **15 s**.

Suggestions use the job's runs over the **last 7 days** (same repository and job
name), not just this run: cache hits make one run's peak misleading. Typecheck in
monorepo-typescript peaks at 1.5 GB in a typical run and 13.1 GB in the worst. The
history comes from two recording rules in monta-app/terraform
(`global/grafana/teams/sre/alerts_arc.tf`): `arc:job_memory_working_set_bytes:max1m`
and `arc:job_cpu_usage_cores:rate1m`. They join each pod's cAdvisor series to its
GitHub job once a minute, so the report never joins raw series at read time.

Memory and CPU are treated differently because the runners have a memory limit
and only a CPU request:

- **Memory is a hard floor.** A size must hold 1.3 × the job's 7-day peak, or the
  job is OOM-killed. A job that needs more gets ⬆️ *needs memory*, and so does
  any job that was OOM-killed in this run.
- **CPU only costs time.** A job whose median CPU is at least 85% of its runner's
  vCPU gets ⬆️ *CPU-bound, faster*. A smaller size must still cover the job's
  median CPU; it is *fits* if it also covers the peak, and *trial: may be slower*
  if not. In service-ocpi, a 4 vCPU runner made every integration shard 17–97 s
  slower, so trial a smaller runner before moving to it.
- **Smaller sizes need 5 runs** in the window, so rare jobs and new recording
  rules don't produce a downsize from one run. Bigger sizes don't wait.

## Files

- `arc_job_report.py` — builds and posts the comment.
- `job_resources.py` — the per-job analysis and the size suggestion. It queries
  Prometheus through Grafana's datasource proxy, with `GRAFANA_TOKEN` in CI or
  `gcx api` locally.
- `test_arc_job_report.py` — unit tests for the comment rendering and the suggestion:
  `python3 -m unittest discover -s .github/actions/arc-job-report -p 'test_*.py'`

## Running locally

With `gh` and a `gcx` context that can read the datasource (no `GRAFANA_TOKEN`
needed), print the comment for any run without posting it:

```bash
python3 .github/actions/arc-job-report/arc_job_report.py \
  https://github.com/monta-app/service-ocpi/actions/runs/36544901752 --dry-run
```
