# ArgoCD Wait for Sync — multi-app

A composite GitHub Action that waits, **concurrently**, for **many** ArgoCD
applications to sync and become healthy at an expected git revision, then emits
one aggregated JSON array with per-app start/end timing.

It is the multi-app sibling of [`argocd-wait-sync`](../argocd-wait-sync). Use
that one for a single application; use this one when a single workflow run
deploys several apps (e.g. a monorepo that bumps many services in one commit)
and you want **one job** that fails fast if any of them fails to converge and
hands the per-app timing to a downstream step.

## Why a separate action

`argocd-wait-sync` is pinned `@main` by many deploy pipelines, so it is left
untouched. This action reuses the same proven per-app state machine (refresh →
detect our revision → wait Synced+Healthy), the same fail-fast conditions, and
the same supersede-via-git-ancestry check, generalized to N apps.

## Multi-source apps (`source-repo`)

Single-source apps report their synced revision in `.status.sync.revision`.
**Multi-source** apps (ArgoCD `spec.sources[]`, e.g. a chart source plus a
separate image-values/manifests source) leave that field empty and report one
revision per source in `.status.sync.revisions[]`.

Set `source-repo` to the substring of the source `repoURL` whose revision you
want to verify against (typically your manifests repo name). The action finds
that source's index and matches your expected revision against
`.status.sync.revisions[<index>]`. Leave `source-repo` empty for single-source
apps.

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `server` | Yes | - | ArgoCD server URL (e.g. `argocd.monta.app`) |
| `auth-token` | Yes | - | ArgoCD auth token |
| `apps` | Yes | - | JSON array of apps to wait for (see below) |
| `timeout` | No | `900` | Overall timeout in seconds for ALL apps |
| `poll-interval` | No | `5` | Polling interval in seconds |
| `source-repo` | No | `''` | Source `repoURL` substring to match for multi-source apps |
| `manifest-repo` | No | `monta-app/kube-manifests` | `owner/repo` for supersede (git ancestry) detection |
| `github-token` | Yes | - | Token for the supersede compare API call |

`apps` entry shape:

```json
[
  { "app": "frontend-hub-production", "revision": "<git-sha>", "name": "Hub" },
  { "app": "portals-production",      "revision": "<git-sha>", "name": "Portals" }
]
```

`name` is an optional display label (defaults to `app`). `revision` is the git
SHA you expect the app to converge to (for a monorepo, the manifests bump
commit — the same for every app in the run).

## Outputs

| Output | Description |
|--------|-------------|
| `deployments` | JSON array `[{ name, app, revision, start, end, status, url }]`, ISO 8601 UTC timestamps |

- `start` = ArgoCD `operationState.startedAt` (sync began)
- `end` = wall-clock UTC captured the moment health first became `Healthy`
- `revision` = the revision verified (may be a superseding commit that includes yours)

## Behavior

- **Fail-fast**: the job exits non-zero the moment any app is `Degraded`,
  `Missing`, its operation `Failed`/`Error`, or its manifests history `diverged`
  from your revision — or when the overall `timeout` elapses with any app not
  yet healthy. Transient `Unknown` (≤30s) and `ComparisonError` (≤60s, with a
  hard refresh) are tolerated.
- **Refresh first**: every app is refreshed up front so ArgoCD detects the new
  revision immediately instead of on its next reconciliation.
- **Supersede-aware**: if a newer bump moved an app past your revision, the
  action confirms your commit is an ancestor (`compare … = ahead`) and treats it
  as success (bundled).

## Example

```yaml
- name: Wait for all deployed apps to be healthy
  id: rollout
  uses: monta-app/github-workflows/.github/actions/argocd-wait-sync-multi@main
  with:
    server: argocd.monta.app
    auth-token: ${{ secrets.ARGOCD_TOKEN_PRODUCTION }}
    github-token: ${{ secrets.MONTA_BOT_TOKEN }}
    source-repo: monorepo-typescript-manifests
    manifest-repo: monta-app/monorepo-typescript-manifests
    apps: ${{ steps.build-apps.outputs.apps }}   # JSON array

- name: Use the timing
  run: echo '${{ steps.rollout.outputs.deployments }}' | jq .
```

## Local testing

Offline (no ArgoCD) — drives the state machine from fixtures:

```bash
bash test/run-tests.sh
```

Live against a real ArgoCD server (needs the ArgoCD CLI — install via the
sibling action's `./install-cli.sh`):

```bash
./test-local.sh \
  --server argocd.monta.app \
  --auth-token "$ARGOCD_TOKEN_PRODUCTION" \
  --source-repo monorepo-typescript-manifests \
  --manifest-repo monta-app/monorepo-typescript-manifests \
  --apps '[{"app":"frontend-hub-production","revision":"<a-recent-manifests-bump-sha>","name":"Hub"}]'
```
