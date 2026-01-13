# ArgoCD Wait for Sync Action

A composite GitHub Action that waits for an ArgoCD application to sync and become healthy after deployment.

## Description

This action installs the ArgoCD CLI and monitors an ArgoCD application until it syncs to a specific git revision and becomes healthy. It uses token-based authentication and is designed to work with auto-sync enabled environments, handling race conditions when triggered immediately after git push.

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `server` | Yes | - | ArgoCD server URL (e.g., `argocd.example.com`) |
| `app-name` | Yes | - | ArgoCD application name |
| `auth-token` | Yes | - | ArgoCD authentication token |
| `revision` | Yes | - | Expected git commit SHA to verify deployment |
| `timeout` | No | `300` | Timeout in seconds to wait for sync completion |
| `namespace` | No | `argocd` | ArgoCD namespace where Application resource is stored |

**Notes:**
- The `revision` parameter enables two-phase monitoring that waits for ArgoCD to detect your change before monitoring health, preventing race conditions when triggered immediately after git push.
- The `namespace` parameter is only used to construct the ArgoCD UI URL. It should be the namespace where your ArgoCD Application resource is stored (typically `argocd`), not where your deployed resources run.

## Outputs

| Output | Description |
|--------|-------------|
| `deployment-start-time` | ISO 8601 timestamp when ArgoCD started the sync operation (UTC) |
| `deployment-end-time` | ISO 8601 timestamp when deployment completed and application became healthy (UTC) |
| `deployment-url` | Direct URL to the application in ArgoCD UI |

These timestamps capture the **full deployment window** including pod rollout:

- **Start time**: From ArgoCD's `operationState.startedAt` - when sync operation began (applying manifests)
- **End time**: Captured via real-time monitoring - the exact moment when health status transitions to "Healthy"

This real-time monitoring approach provides:
- Real signal for start time (from ArgoCD metadata, avoiding race conditions)
- Real signal for completion (captured the moment health status changes to "Healthy")
- Accurate deployment window including Kubernetes rollout (minutes, not just sync seconds)
- 5-second polling interval to capture health transition as soon as it occurs

Useful for:
- Correlating regressions with specific deployments
- Determining if issues occurred during or after deployment
- Tracking actual deployment duration (including pod rollout)
- Debugging timing-related issues
- Accurate time windows for auto-synced deployments

## Usage

### Basic Usage

```yaml
- name: Wait for ArgoCD sync
  uses: monta-app/github-workflows/.github/actions/argocd-wait-sync@main
  with:
    server: argocd.example.com
    app-name: my-service-production
    auth-token: ${{ secrets.ARGOCD_TOKEN }}
    revision: ${{ github.sha }}  # Verify we're tracking the right deployment
```

### With Custom Timeout

```yaml
- name: Wait for ArgoCD sync
  uses: monta-app/github-workflows/.github/actions/argocd-wait-sync@main
  with:
    server: argocd.example.com
    app-name: my-service-staging
    auth-token: ${{ secrets.ARGOCD_TOKEN }}
    revision: ${{ github.sha }}
    timeout: 600  # Wait up to 10 minutes
```

### In a Deployment Workflow

```yaml
jobs:
  deploy:
    name: Deploy
    runs-on: ubuntu-latest
    steps:
      - name: Deploy to Kubernetes
        run: |
          # Your deployment steps (e.g., update kube-manifests)
          kubectl apply -f manifests/

      - name: Wait for ArgoCD to sync
        uses: monta-app/github-workflows/.github/actions/argocd-wait-sync@main
        with:
          server: ${{ secrets.ARGOCD_SERVER }}
          app-name: ${{ inputs.service-identifier }}-${{ inputs.stage }}
          auth-token: ${{ secrets.ARGOCD_TOKEN }}
          revision: ${{ github.sha }}
          timeout: 300
```

### With Outputs for Tracking Deployment Time Window

```yaml
jobs:
  deploy:
    name: Deploy
    runs-on: ubuntu-latest
    steps:
      - name: Deploy to Kubernetes
        run: |
          kubectl apply -f manifests/

      - name: Wait for ArgoCD to sync
        id: argocd-sync
        uses: monta-app/github-workflows/.github/actions/argocd-wait-sync@main
        with:
          server: ${{ secrets.ARGOCD_SERVER }}
          app-name: my-service-production
          auth-token: ${{ secrets.ARGOCD_TOKEN }}
          revision: ${{ github.sha }}

      - name: Report deployment window
        run: |
          echo "Deployment started: ${{ steps.argocd-sync.outputs.deployment-start-time }}"
          echo "Deployment completed: ${{ steps.argocd-sync.outputs.deployment-end-time }}"
          echo "ArgoCD UI: ${{ steps.argocd-sync.outputs.deployment-url }}"

      - name: Comment on PR with deployment info
        if: github.event_name == 'pull_request'
        uses: actions/github-script@v7
        with:
          script: |
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: `🚀 Deployment completed!

              **Time window:**
              - Started: ${{ steps.argocd-sync.outputs.deployment-start-time }}
              - Completed: ${{ steps.argocd-sync.outputs.deployment-end-time }}

              [View in ArgoCD](${{ steps.argocd-sync.outputs.deployment-url }})`
            })

      - name: Log to monitoring system
        run: |
          curl -X POST https://monitoring.example.com/api/deployments \
            -d "service=my-service" \
            -d "start=${{ steps.argocd-sync.outputs.deployment-start-time }}" \
            -d "end=${{ steps.argocd-sync.outputs.deployment-end-time }}" \
            -d "argocd_url=${{ steps.argocd-sync.outputs.deployment-url }}"
```

## Prerequisites

### ArgoCD Authentication Token

You need to generate an ArgoCD authentication token and store it as a GitHub secret.

**Generate a token:**

1. Login to ArgoCD UI
2. Go to **Settings → Accounts** (or User Info → Auth Tokens)
3. Generate a new token for your account (e.g., `actions-runner`)
4. Copy the token
5. Add it to your GitHub repository secrets as `ARGOCD_TOKEN`

The action uses token-based authentication, passing the token directly to ArgoCD CLI commands without requiring a login session. This works reliably in CI/CD environments.

## Revision Verification

This action requires a `revision` parameter to ensure accurate tracking and prevent race conditions. The revision verification process:

1. **Waits for ArgoCD to detect** your expected revision
2. **Monitors the deployment** of that specific revision
3. **Verifies the final state** matches your expected commit SHA
4. **Fails if there's a mismatch** to prevent tracking wrong deployments

Always pass your commit SHA (typically `${{ github.sha }}`):

```yaml
- name: Wait for ArgoCD sync
  uses: monta-app/github-workflows/.github/actions/argocd-wait-sync@main
  with:
    server: argocd.example.com
    app-name: my-service
    auth-token: ${{ secrets.ARGOCD_TOKEN }}
    revision: ${{ github.sha }}  # Required
```

This ensures the timestamps correspond to the deployment you actually care about, not a previous or subsequent deployment.

## Handling Race Conditions After Git Push

When triggering this action immediately after pushing to kube-manifests, there's a timing gap before ArgoCD detects the change (ArgoCD typically polls git every 3 minutes). The action handles this intelligently:

### Timeline Example
```
T+0s:    Git push completes
T+0s:    [Action starts monitoring]
T+0-3m:  ArgoCD hasn't detected change yet
         App shows: Synced + Healthy (OLD revision)
         Action: Waits, doesn't exit immediately ✓
T+3m:    ArgoCD detects change
         App shows: Syncing (NEW revision)
         Action: Confirms deployment started ✓
T+5m:    Deployment completes
         App shows: Healthy (NEW revision)
         Action: Captures timestamp ✓
```

### Two-Phase Monitoring

**Phase 1: Wait for ArgoCD to Detect**
- Polls until the expected revision appears
- Prevents exiting early when app is healthy with old revision
- Shows: "Waiting for ArgoCD to detect new revision"

**Phase 2: Wait for Health**
- Once expected revision detected, monitors for health transition
- Captures exact timestamp when status becomes Healthy
- Shows: "Application became healthy at: ..."

### Edge Cases Handled

**If deployment already completed:**
- Detected: App already healthy with expected revision
- Behavior: Warns and uses current timestamp
- Warning: "Application already healthy with expected revision - deployment completed before monitoring started"

**If revision never appears:**
- Times out after configured timeout (default 300s)
- Error: "Timeout waiting for application to become healthy"

This two-phase approach ensures accurate tracking even when triggered immediately after git push.

## What This Action Does

1. **Installs ArgoCD CLI**: Downloads the latest ArgoCD CLI binary
2. **Authenticates**: Logs in to your ArgoCD server using the provided token
3. **Phase 1 - Wait for Detection**: Polls until ArgoCD detects your expected revision (handles git push timing gap)
4. **Phase 2 - Monitor Health**: Once revision detected, monitors until health status becomes "Healthy"
5. **Captures Timestamps**: Records the exact moment when health transition occurs
6. **Extracts Start Time**: Retrieves deployment start time from ArgoCD's `operationState.startedAt`
7. **Verifies Revision**: Confirms the deployed revision matches your expected commit
8. **Reports Status**: Exits successfully when healthy and verified, or fails on timeout/mismatch

## Error Handling

The action provides **fail-fast behavior** for deployment failures:

### Immediate Failures (no timeout wait)

The action fails immediately when ArgoCD reports:

- **Degraded**: Resources have failed or cannot become healthy
  - Example: Pods crash-looping, failed liveness/readiness probes
  - Shows full application details and resource status for debugging

- **Missing**: Resources don't exist in the cluster
  - Example: Namespace doesn't exist, RBAC prevents creation

- **Operation Failed/Error**: Sync operation encountered an error
  - Example: Invalid manifests, webhook admission rejection
  - Shows operation message and details

- **Unknown** (after 30s): Health assessment failed
  - Gives 30 seconds grace period for transient issues
  - Example: Network issues querying Kubernetes API

### Timeout Failures

The action times out (default 300s) if:
- ArgoCD doesn't detect the expected revision
- Deployment stays in "Progressing" state too long
- Application never reaches "Healthy" state

### Other Failures

- ArgoCD server unreachable
- Authentication token invalid
- Deployed revision doesn't match expected revision

### Successful Statuses

The action continues monitoring when status is:
- **Progressing**: Deployment in progress (normal during rollout)
- **Suspended**: Resources paused (waits for resume)
- **Synced + Healthy**: Success!

## Testing Locally

You can test this action locally before using it in workflows. The action uses a shared `wait-sync.sh` script that you can run directly for testing.

### First-Time Setup (One Time Only)

```bash
cd .github/actions/argocd-wait-sync

# Install ArgoCD CLI
./install-cli.sh

# Configure credentials
./setup-env.sh
```

### Running Tests

```bash
# Test with specific application and revision
./test-local.sh \
  --app-name my-service-production \
  --revision abc123def
```

The test script uses the same `wait-sync.sh` that runs in GitHub Actions, ensuring you're testing the exact code that will run in CI. The script automatically loads credentials from your `.env` file and uses token-based authentication.

**Troubleshooting:**

If the test fails with connection errors, verify your token is valid:
```bash
source .env
argocd app list --auth-token="$ARGOCD_AUTH_TOKEN" --server="$ARGOCD_SERVER" --grpc-web --insecure
```

This should list your applications. If it fails, you may need to generate a new token in the ArgoCD UI.

## Notes

- The action uses `--insecure` flag for TLS connections. If you need strict TLS validation, modify the `ARGOCD_FLAGS` in `wait-sync.sh`.
- The action uses `--grpc-web` for better compatibility with load balancers and proxies.
- Token-based authentication is used directly with each ArgoCD CLI command, no login session needed.
