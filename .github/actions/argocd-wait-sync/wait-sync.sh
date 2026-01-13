#!/usr/bin/env bash
set -euo pipefail

# ArgoCD Wait-Sync Script
# This script monitors an ArgoCD application and waits for it to sync and become healthy
# with a specific git revision. It handles race conditions when triggered after git push.
#
# Required Environment Variables:
#   ARGOCD_SERVER      - ArgoCD server URL
#   ARGOCD_AUTH_TOKEN  - ArgoCD authentication token
#   APP_NAME           - ArgoCD application name
#   EXPECTED_REVISION  - Git commit SHA to verify
#
# Optional Environment Variables:
#   TIMEOUT           - Timeout in seconds (default: 300)
#   POLL_INTERVAL     - Polling interval in seconds (default: 5)
#
# Health Status Handling:
#   Healthy      - Success, deployment complete
#   Progressing  - Keep waiting, deployment in progress
#   Degraded     - Fail immediately, resources failed
#   Missing      - Fail immediately, resources don't exist
#   Suspended    - Keep waiting, resources paused
#   Unknown      - Fail after 30s, health assessment failed
#
# Exit Codes:
#   0 - Success (application healthy with expected revision)
#   1 - Failure (timeout, degraded, missing, or operation failed)

# Validate required environment variables
if [ -z "${ARGOCD_SERVER:-}" ]; then
    echo "::error::ARGOCD_SERVER environment variable is required"
    exit 1
fi

if [ -z "${ARGOCD_AUTH_TOKEN:-}" ]; then
    echo "::error::ARGOCD_AUTH_TOKEN environment variable is required"
    exit 1
fi

if [ -z "${APP_NAME:-}" ]; then
    echo "::error::APP_NAME environment variable is required"
    exit 1
fi

if [ -z "${EXPECTED_REVISION:-}" ]; then
    echo "::error::EXPECTED_REVISION environment variable is required"
    exit 1
fi

# Set defaults
TIMEOUT="${TIMEOUT:-300}"
POLL_INTERVAL="${POLL_INTERVAL:-5}"

# ArgoCD CLI flags - pass auth token directly (no login session needed)
ARGOCD_FLAGS=(
    "--auth-token=$ARGOCD_AUTH_TOKEN"
    "--server=$ARGOCD_SERVER"
    "--grpc-web"
    "--insecure"
)

echo "Monitoring ArgoCD application '$APP_NAME' for sync and health..."
echo "Expected revision: ${EXPECTED_REVISION:0:7}"
echo "Timeout: ${TIMEOUT}s"
echo ""

START=$(date +%s)
DEPLOYMENT_STARTED=false
HEALTH_ACHIEVED=false
HEALTH_TIMESTAMP=""
MISSED_DEPLOYMENT=false

while true; do
    ELAPSED=$(($(date +%s) - START))

    if [ $ELAPSED -ge $TIMEOUT ]; then
        echo "::error::Timeout waiting for application to become healthy after ${TIMEOUT}s"
        exit 1
    fi

    # Get current app status
    APP_INFO=$(argocd app get "$APP_NAME" -o json "${ARGOCD_FLAGS[@]}" 2>/dev/null || echo "{}")

    SYNC_STATUS=$(echo "$APP_INFO" | jq -r '.status.sync.status // "Unknown"')
    HEALTH_STATUS=$(echo "$APP_INFO" | jq -r '.status.health.status // "Unknown"')
    CURRENT_REVISION=$(echo "$APP_INFO" | jq -r '.status.sync.revision // ""')

    echo "[$ELAPSED/${TIMEOUT}s] Sync: $SYNC_STATUS, Health: $HEALTH_STATUS, Rev: ${CURRENT_REVISION:0:7}"

    # Check for explicit failure states and fail fast
    if [ "$HEALTH_STATUS" = "Degraded" ]; then
        echo "::error::Application health is Degraded - deployment failed"
        echo "Retrieving failure details from ArgoCD..."
        argocd app get "$APP_NAME" "${ARGOCD_FLAGS[@]}" || true
        echo ""
        echo "::error::Check the output above for specific resource failures"
        exit 1
    fi

    if [ "$HEALTH_STATUS" = "Missing" ]; then
        echo "::error::Application health is Missing - resources don't exist in cluster"
        argocd app get "$APP_NAME" "${ARGOCD_FLAGS[@]}" || true
        exit 1
    fi

    if [ "$SYNC_STATUS" = "Unknown" ] && [ "$ELAPSED" -gt 30 ]; then
        # Give it 30 seconds before failing on Unknown status (might be transient)
        echo "::error::Application sync status is Unknown after 30s"
        argocd app get "$APP_NAME" "${ARGOCD_FLAGS[@]}" || true
        exit 1
    fi

    # Check operation phase for failures
    OPERATION_PHASE=$(echo "$APP_INFO" | jq -r '.status.operationState.phase // ""')
    if [ "$OPERATION_PHASE" = "Failed" ] || [ "$OPERATION_PHASE" = "Error" ]; then
        echo "::error::ArgoCD operation failed with phase: $OPERATION_PHASE"
        OPERATION_MESSAGE=$(echo "$APP_INFO" | jq -r '.status.operationState.message // "No message"')
        echo "::error::Operation message: $OPERATION_MESSAGE"
        echo ""
        echo "Retrieving full application details..."
        argocd app get "$APP_NAME" "${ARGOCD_FLAGS[@]}" || true
        exit 1
    fi

    # Check if current revision matches expected
    REVISION_MATCHES=false
    if [ -n "$CURRENT_REVISION" ] && [[ "$CURRENT_REVISION" =~ ^${EXPECTED_REVISION} ]]; then
        REVISION_MATCHES=true
    fi

    # Phase 1: Wait for deployment to start (revision matches + not fully healthy yet)
    # This handles the case where ArgoCD hasn't detected our git push yet
    if [ "$DEPLOYMENT_STARTED" = false ]; then
        if [ "$REVISION_MATCHES" = true ]; then
            # We found our revision!
            if [ "$SYNC_STATUS" = "Synced" ] && [ "$HEALTH_STATUS" = "Healthy" ]; then
                # Already healthy with our revision - we missed the deployment!
                echo "::warning::Application already healthy with expected revision - deployment completed before monitoring started"
                MISSED_DEPLOYMENT=true
                DEPLOYMENT_STARTED=true
                HEALTH_ACHIEVED=true
                # Use current time since we missed the actual transition
                HEALTH_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
                break
            else
                # Found our revision and it's deploying!
                echo "✓ ArgoCD detected our revision, deployment in progress"
                DEPLOYMENT_STARTED=true
            fi
        else
            # Still waiting for ArgoCD to detect our revision
            echo "  Waiting for ArgoCD to detect new revision (current: ${CURRENT_REVISION:0:7}, expected: ${EXPECTED_REVISION:0:7})"
        fi
    fi

    # Phase 2: Monitor for health transition (once we've confirmed deployment started)
    if [ "$DEPLOYMENT_STARTED" = true ] && [ "$HEALTH_ACHIEVED" = false ]; then
        if [ "$SYNC_STATUS" = "Synced" ] && [ "$HEALTH_STATUS" = "Healthy" ]; then
            # Capture timestamp the moment we detect health
            HEALTH_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
            echo "✓ Application became healthy at: $HEALTH_TIMESTAMP"
            HEALTH_ACHIEVED=true
            break
        fi
    fi

    sleep $POLL_INTERVAL
done

if [ "$MISSED_DEPLOYMENT" = true ]; then
    echo "::warning::Used current timestamp instead of actual deployment time"
    echo "::warning::To capture accurate timestamps, trigger this action sooner after git push"
fi

echo ""
echo "Application '$APP_NAME' is synced and healthy!"

# Get deployment start time and verify revision
echo ""
echo "Retrieving deployment information from ArgoCD..."
APP_INFO=$(argocd app get "$APP_NAME" -o json "${ARGOCD_FLAGS[@]}")

# Get deployment start time from ArgoCD's operationState
START_TIME=$(echo "$APP_INFO" | jq -r '.status.operationState.startedAt // empty')

if [ -z "$START_TIME" ]; then
    echo "::warning::Could not retrieve operation start time from ArgoCD, using current time"
    START_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
fi

echo "Deployment started at: $START_TIME (from ArgoCD operationState)"

# Verify revision
DEPLOYED_REVISION=$(echo "$APP_INFO" | jq -r '.status.sync.revision // empty')
echo "Expected revision: $EXPECTED_REVISION"
echo "Deployed revision: $DEPLOYED_REVISION"

if [ -z "$DEPLOYED_REVISION" ]; then
    echo "::error::Could not determine deployed revision from ArgoCD"
    exit 1
fi

# Check if deployed revision starts with expected revision (allows short SHAs)
if [[ ! "$DEPLOYED_REVISION" =~ ^${EXPECTED_REVISION} ]]; then
    echo "::error::Revision mismatch! Expected: $EXPECTED_REVISION, Deployed: $DEPLOYED_REVISION"
    echo "::error::The synced application is not running the expected revision."
    echo "::error::This could mean auto-sync already completed with a different commit,"
    echo "::error::or the sync operation deployed an unexpected version."
    exit 1
fi

echo "✓ Revision verified: $DEPLOYED_REVISION"
echo ""

# Output results
echo "=========================================="
echo "Deployment Complete"
echo "=========================================="
echo "Start Time:  $START_TIME"
echo "End Time:    $HEALTH_TIMESTAMP"
echo "=========================================="
echo ""

# Export outputs for GitHub Actions (if GITHUB_OUTPUT is set)
if [ -n "${GITHUB_OUTPUT:-}" ]; then
    echo "deployment-start-time=$START_TIME" >> "$GITHUB_OUTPUT"
    echo "deployment-end-time=$HEALTH_TIMESTAMP" >> "$GITHUB_OUTPUT"
    echo "missed-deployment=$MISSED_DEPLOYMENT" >> "$GITHUB_OUTPUT"
fi

# Also output to stdout for local testing
echo "OUTPUT: deployment-start-time=$START_TIME"
echo "OUTPUT: deployment-end-time=$HEALTH_TIMESTAMP"
echo "OUTPUT: missed-deployment=$MISSED_DEPLOYMENT"
