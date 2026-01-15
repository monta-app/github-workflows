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
MANIFEST_REPO="${MANIFEST_REPO:-monta-app/kube-manifests}"

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
VERIFIED_REVISION=""

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

    # Check for ComparisonError condition
    COMPARISON_ERROR=$(echo "$APP_INFO" | jq -r '.status.conditions[] | select(.type == "ComparisonError") | .message // ""' 2>/dev/null || echo "")

    if [ -n "$COMPARISON_ERROR" ]; then
        echo "::warning::ArgoCD ComparisonError detected: $COMPARISON_ERROR"

        # Attempt hard refresh to clear corrupted cache
        if [ "$ELAPSED" -eq 5 ] || [ "$ELAPSED" -eq 10 ]; then
            echo "  Attempting hard refresh to clear ArgoCD cache..."
            argocd app get "$APP_NAME" --hard-refresh "${ARGOCD_FLAGS[@]}" &>/dev/null || true
            echo "  Hard refresh triggered, waiting for ArgoCD to recompute state..."
        fi

        if [ "$ELAPSED" -gt 60 ]; then
            # Give it 60 seconds to resolve ComparisonError with hard refresh
            echo "::error::ArgoCD ComparisonError persists after 60s and hard refresh attempts"
            echo "::error::This indicates a server-side issue with ArgoCD's repository cache"
            echo "::error::ComparisonError: $COMPARISON_ERROR"
            argocd app get "$APP_NAME" "${ARGOCD_FLAGS[@]}" || true
            exit 1
        fi
    elif [ "$SYNC_STATUS" = "Unknown" ] && [ "$ELAPSED" -gt 30 ]; then
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
                # Capture the verified revision before breaking
                VERIFIED_REVISION="$CURRENT_REVISION"
                break
            else
                # Found our revision and it's deploying!
                echo "✓ ArgoCD detected our revision, deployment in progress"
                DEPLOYMENT_STARTED=true
            fi
        else
            # Still waiting for ArgoCD to detect our revision
            echo "  Waiting for ArgoCD to detect new revision (current: ${CURRENT_REVISION:0:7}, expected: ${EXPECTED_REVISION:0:7})"

            # Check if current revision is ahead of expected revision (deployment was superseded)
            # This requires GitHub CLI to check commit ancestry in manifest repo
            if command -v gh &> /dev/null && [ -n "$CURRENT_REVISION" ] && [ "$ELAPSED" -gt 30 ]; then
                # Only check after 30s to avoid false positives during initial polling
                echo "  Running supersede detection check..."

                # Use GitHub API to check if expected revision is an ancestor of current revision
                # Disable pipefail temporarily to capture errors without exiting
                set +e
                COMPARE_STATUS=$(gh api repos/${MANIFEST_REPO}/compare/${EXPECTED_REVISION}...${CURRENT_REVISION} --jq '.status' 2>&1)
                COMPARE_EXIT_CODE=$?
                set -e

                if [ $COMPARE_EXIT_CODE -ne 0 ]; then
                    echo "  Warning: Failed to check commit ancestry (exit code: $COMPARE_EXIT_CODE)"
                    echo "  Response: $COMPARE_STATUS"
                elif [ -z "$COMPARE_STATUS" ] || [ "$COMPARE_STATUS" = "null" ]; then
                    echo "  Warning: Comparison returned empty or null status"
                else
                    echo "  Comparison result: ${EXPECTED_REVISION:0:7}...${CURRENT_REVISION:0:7} = $COMPARE_STATUS"

                    if [ "$COMPARE_STATUS" = "ahead" ] || [ "$COMPARE_STATUS" = "diverged" ]; then
                        echo "::error::Deployment superseded - ArgoCD moved to a newer commit"
                        echo "::error::Expected revision: $EXPECTED_REVISION"
                        echo "::error::Current revision: $CURRENT_REVISION"
                        echo "::error::Comparison status: $COMPARE_STATUS"
                        echo "::error::Another service deployed after yours, and ArgoCD skipped your commit."
                        echo "::error::Your changes are still in the manifest, but were deployed as part of the newer commit."
                        exit 1
                    fi
                fi
            fi
        fi
    fi

    # Phase 2: Monitor for health transition (once we've confirmed deployment started)
    if [ "$DEPLOYMENT_STARTED" = true ] && [ "$HEALTH_ACHIEVED" = false ]; then
        if [ "$SYNC_STATUS" = "Synced" ] && [ "$HEALTH_STATUS" = "Healthy" ]; then
            # Capture timestamp and revision the moment we detect health
            HEALTH_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
            VERIFIED_REVISION="$CURRENT_REVISION"
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

# Verify we have the revision we captured during monitoring
if [ -z "$VERIFIED_REVISION" ]; then
    echo "::error::Internal error: No revision was captured during monitoring"
    exit 1
fi

echo "Expected revision: $EXPECTED_REVISION"
echo "Deployed revision: $VERIFIED_REVISION (captured when health achieved)"

# Get deployment start time from ArgoCD's operationState
# Note: We fetch this separately to get accurate start time, but use VERIFIED_REVISION
# which was captured during the monitoring loop, not the current revision
echo ""
echo "Retrieving deployment start time from ArgoCD..."
APP_INFO=$(argocd app get "$APP_NAME" -o json "${ARGOCD_FLAGS[@]}")
START_TIME=$(echo "$APP_INFO" | jq -r '.status.operationState.startedAt // empty')

if [ -z "$START_TIME" ]; then
    echo "::warning::Could not retrieve operation start time from ArgoCD, using current time"
    START_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
fi

echo "Deployment started at: $START_TIME (from ArgoCD operationState)"

# Note: We already verified VERIFIED_REVISION matches EXPECTED_REVISION during the
# monitoring loop, so we don't need to check again. This allows the action to succeed
# even if another deployment happened after ours and ArgoCD moved to a newer revision.

echo "✓ Revision verified: $VERIFIED_REVISION"
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
