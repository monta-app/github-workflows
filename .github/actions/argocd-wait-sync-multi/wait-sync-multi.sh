#!/usr/bin/env bash
set -euo pipefail

# ArgoCD Multi-App Wait-Sync Script
#
# Waits for MANY ArgoCD applications to sync and become healthy at an expected
# git revision, concurrently, in a single job. Fail-fast: the moment any app is
# Degraded/Missing/failed/diverged, or the overall timeout elapses with any app
# not yet Healthy, the script exits non-zero. On success it emits one aggregated
# JSON array with per-app start/end timing for downstream steps (e.g. a
# changelog message).
#
# This is the multi-app generalization of the sibling argocd-wait-sync action.
# It reuses the same per-app state machine (refresh -> detect our revision ->
# wait Synced+Healthy), the same failure conditions, and the same
# supersede-via-git-ancestry check. The one added capability is SOURCE_REPO:
# multi-source ArgoCD apps expose per-source revisions in
# `.status.sync.revisions[]` (the singular `.status.sync.revision` is empty), so
# SOURCE_REPO selects which source's revision to match against.
#
# Required environment variables:
#   ARGOCD_SERVER      - ArgoCD server URL (without https://)
#   ARGOCD_AUTH_TOKEN  - ArgoCD authentication token
#   APPS_JSON          - JSON array of apps to wait for. Each entry:
#                          { "app": "<argocd app name>",
#                            "revision": "<expected git SHA>",
#                            "name": "<display name, optional, defaults to app>" }
#
# Optional environment variables:
#   TIMEOUT            - Overall timeout in seconds (default: 900)
#   POLL_INTERVAL      - Polling interval in seconds (default: 5)
#   SOURCE_REPO        - When set, match the expected revision against the
#                        `.status.sync.revisions[]` entry whose source repoURL
#                        contains this string (e.g. a manifests repo name).
#                        When unset, use the singular `.status.sync.revision`
#                        (single-source apps — same behavior as argocd-wait-sync).
#   MANIFEST_REPO      - owner/repo used for supersede detection (git ancestry
#                        compare). Defaults to monta-app/kube-manifests.
#   GITHUB_TOKEN       - token for the supersede compare API call.
#   FIXTURE_DIR        - TEST ONLY. When set, `argocd app get` is not called;
#                        instead app JSON is read from
#                        $FIXTURE_DIR/<app>.<tick>.json (falling back to
#                        <app>.json), letting the state machine be driven offline.
#
# Exit codes: 0 = every app synced+healthy at (or bundled into) its revision.
#             1 = validation error, any app failed, or timeout.

# --- validation -------------------------------------------------------------

for var in ARGOCD_SERVER ARGOCD_AUTH_TOKEN APPS_JSON; do
    if [ -z "${!var:-}" ]; then
        echo "::error::$var environment variable is required"
        exit 1
    fi
done

if ! echo "$APPS_JSON" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1; then
    echo "::error::APPS_JSON must be a non-empty JSON array"
    exit 1
fi

TIMEOUT="${TIMEOUT:-900}"
POLL_INTERVAL="${POLL_INTERVAL:-5}"
SOURCE_REPO="${SOURCE_REPO:-}"
MANIFEST_REPO="${MANIFEST_REPO:-monta-app/kube-manifests}"
FIXTURE_DIR="${FIXTURE_DIR:-}"

ARGOCD_FLAGS=(
    "--auth-token=$ARGOCD_AUTH_TOKEN"
    "--server=$ARGOCD_SERVER"
    "--grpc-web"
    "--insecure"
)

# --- parse app list into parallel indexed arrays (bash 3.2 compatible) -------

APP_NAMES=()
EXPECTED_REVS=()
DISPLAY_NAMES=()
while IFS=$'\t' read -r app rev name; do
    APP_NAMES+=("$app")
    EXPECTED_REVS+=("$rev")
    DISPLAY_NAMES+=("$name")
done < <(echo "$APPS_JSON" | jq -r '.[] | [.app, .revision, (.name // .app)] | @tsv')

N=${#APP_NAMES[@]}

# Per-app state. STATE ∈ pending | started | done
STATE=()
START_AT=()          # ArgoCD operationState.startedAt (ISO)
END_AT=()            # wall-clock UTC when first observed Synced+Healthy
VERIFIED_REV=()      # the revision we verified (may be a superseding SHA)
UNKNOWN_SINCE=()     # epoch when SYNC first went Unknown (transient tolerance)
CERROR_SINCE=()      # epoch when a ComparisonError was first seen
CERROR_REFRESHED=()  # whether we already hard-refreshed this app for a ComparisonError
for ((i = 0; i < N; i++)); do
    STATE+=("pending"); START_AT+=(""); END_AT+=(""); VERIFIED_REV+=("")
    UNKNOWN_SINCE+=(""); CERROR_SINCE+=(""); CERROR_REFRESHED+=("false")
done

echo "Waiting for $N application(s) to sync and become healthy..."
for ((i = 0; i < N; i++)); do
    echo "  - ${DISPLAY_NAMES[$i]} (app=${APP_NAMES[$i]}, rev=${EXPECTED_REVS[$i]:0:7})"
done
if [ -n "$SOURCE_REPO" ]; then
    echo "Matching revision against source repo containing: $SOURCE_REPO"
fi
echo "Timeout: ${TIMEOUT}s, poll: ${POLL_INTERVAL}s"
echo ""

# --- helpers ----------------------------------------------------------------

now_epoch() { date +%s; }
now_iso() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

# Fetch one app's status JSON. Overridable via FIXTURE_DIR for offline tests.
TICK=0
get_app_info() {
    local app="$1"
    if [ -n "$FIXTURE_DIR" ]; then
        if [ -f "$FIXTURE_DIR/$app.$TICK.json" ]; then
            cat "$FIXTURE_DIR/$app.$TICK.json"
        elif [ -f "$FIXTURE_DIR/$app.json" ]; then
            cat "$FIXTURE_DIR/$app.json"
        else
            echo "{}"
        fi
        return 0
    fi
    argocd app get "$app" -o json "${ARGOCD_FLAGS[@]}" 2>/dev/null || echo "{}"
}

# Extract the revision we care about from an app's status JSON, honoring
# SOURCE_REPO for multi-source apps.
extract_revision() {
    local info="$1"
    if [ -n "$SOURCE_REPO" ]; then
        echo "$info" | jq -r --arg repo "$SOURCE_REPO" '
            (.spec.sources // []) as $srcs
            | ($srcs | to_entries | map(select(.value.repoURL | contains($repo))) | (.[0].key // null)) as $idx
            | if $idx == null then (.status.sync.revision // "")
              else ((.status.sync.revisions // [])[$idx] // "") end
        '
    else
        echo "$info" | jq -r '.status.sync.revision // ""'
    fi
}

refresh_app() {
    local app="$1"
    [ -n "$FIXTURE_DIR" ] && return 0
    argocd app get "$app" --refresh "${ARGOCD_FLAGS[@]}" &>/dev/null || true
}

# Print a summary of every app's state, then exit 1.
fail_out() {
    local reason="$1"
    echo ""
    echo "::error::$reason"
    echo "---- rollout summary ----"
    for ((i = 0; i < N; i++)); do
        echo "  ${DISPLAY_NAMES[$i]}: ${STATE[$i]}  (rev ${EXPECTED_REVS[$i]:0:7}${VERIFIED_REV[$i]:+ -> ${VERIFIED_REV[$i]:0:7}})"
    done
    exit 1
}

# --- initial refresh (skip ArgoCD's 0-4 min reconciliation lag) -------------

echo "Triggering ArgoCD refresh on all apps..."
for ((i = 0; i < N; i++)); do
    refresh_app "${APP_NAMES[$i]}"
done
echo ""

# --- main concurrent poll loop ----------------------------------------------

START=$(now_epoch)

while true; do
    ELAPSED=$(( $(now_epoch) - START ))

    if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
        for ((i = 0; i < N; i++)); do
            [ "${STATE[$i]}" != "done" ] && STATE[$i]="timeout"
        done
        fail_out "Timeout after ${TIMEOUT}s waiting for all apps to become healthy"
    fi

    ALL_DONE=true

    for ((i = 0; i < N; i++)); do
        [ "${STATE[$i]}" = "done" ] && continue
        ALL_DONE=false

        app="${APP_NAMES[$i]}"
        expected="${EXPECTED_REVS[$i]}"
        display="${DISPLAY_NAMES[$i]}"

        info=$(get_app_info "$app")
        sync_status=$(echo "$info" | jq -r '.status.sync.status // "Unknown"')
        health_status=$(echo "$info" | jq -r '.status.health.status // "Unknown"')
        op_phase=$(echo "$info" | jq -r '.status.operationState.phase // ""')
        current_rev=$(extract_revision "$info")

        echo "[$ELAPSED/${TIMEOUT}s] $display: Sync=$sync_status Health=$health_status Rev=${current_rev:0:7}"

        # -- fail-fast: unrecoverable health/operation states --
        if [ "$health_status" = "Degraded" ]; then
            argocd app get "$app" "${ARGOCD_FLAGS[@]}" 2>/dev/null || true
            fail_out "$display: application health is Degraded"
        fi
        if [ "$health_status" = "Missing" ]; then
            argocd app get "$app" "${ARGOCD_FLAGS[@]}" 2>/dev/null || true
            fail_out "$display: application health is Missing (resources absent)"
        fi
        if [ "$op_phase" = "Failed" ] || [ "$op_phase" = "Error" ]; then
            op_msg=$(echo "$info" | jq -r '.status.operationState.message // "No message"')
            fail_out "$display: ArgoCD operation $op_phase - $op_msg"
        fi

        # -- ComparisonError: hard-refresh once, tolerate 60s --
        comparison_error=$(echo "$info" | jq -r 'first(.status.conditions[]? | select(.type == "ComparisonError") | .message) // ""' 2>/dev/null || true)
        if [ -n "$comparison_error" ]; then
            if [ -z "${CERROR_SINCE[$i]}" ]; then
                CERROR_SINCE[$i]=$(now_epoch)
            fi
            if [ "${CERROR_REFRESHED[$i]}" = "false" ]; then
                echo "  $display: ComparisonError, attempting hard refresh"
                [ -z "$FIXTURE_DIR" ] && { argocd app get "$app" --hard-refresh "${ARGOCD_FLAGS[@]}" &>/dev/null || true; }
                CERROR_REFRESHED[$i]="true"
            fi
            if [ $(( $(now_epoch) - CERROR_SINCE[$i] )) -gt 60 ]; then
                fail_out "$display: ComparisonError persisted >60s - $comparison_error"
            fi
        else
            CERROR_SINCE[$i]=""
            CERROR_REFRESHED[$i]="false"
        fi

        # -- Unknown sync status: tolerate 30s of transient --
        if [ "$sync_status" = "Unknown" ]; then
            if [ -z "${UNKNOWN_SINCE[$i]}" ]; then
                UNKNOWN_SINCE[$i]=$(now_epoch)
            elif [ $(( $(now_epoch) - UNKNOWN_SINCE[$i] )) -gt 30 ]; then
                fail_out "$display: sync status Unknown >30s"
            fi
        else
            UNKNOWN_SINCE[$i]=""
        fi

        # -- does the app's current revision match what we deployed? --
        revision_matches=false
        if [ -n "$current_rev" ] && [ "${current_rev#"$expected"}" != "$current_rev" ]; then
            revision_matches=true
        fi

        # Phase 1: wait for ArgoCD to detect our revision.
        if [ "${STATE[$i]}" = "pending" ]; then
            if [ "$revision_matches" = true ]; then
                VERIFIED_REV[$i]="$current_rev"
                if [ "$sync_status" = "Synced" ] && [ "$health_status" = "Healthy" ]; then
                    # Already healthy at our revision — we joined late; use now().
                    STATE[$i]="done"
                    START_AT[$i]=$(echo "$info" | jq -r '.status.operationState.startedAt // empty')
                    [ -z "${START_AT[$i]}" ] && START_AT[$i]=$(now_iso)
                    END_AT[$i]=$(now_iso)
                    echo "  ✓ $display already healthy at expected revision"
                    continue
                fi
                echo "  ✓ $display: ArgoCD detected our revision, rollout in progress"
                STATE[$i]="started"
            elif [ -n "$current_rev" ] && [ "$ELAPSED" -gt 30 ]; then
                # Revision differs after 30s: maybe a newer bump superseded ours.
                # Our commit is fine if it's an ancestor of the deployed one.
                set +e
                compare_status=$(gh api "repos/${MANIFEST_REPO}/compare/${expected}...${current_rev}" --jq '.status' 2>/dev/null)
                set -e
                if [ "$compare_status" = "ahead" ]; then
                    echo "::warning::$display: deployed a newer revision that includes your change (bundled)"
                    VERIFIED_REV[$i]="$current_rev"
                    STATE[$i]="started"
                    if [ "$sync_status" = "Synced" ] && [ "$health_status" = "Healthy" ]; then
                        STATE[$i]="done"
                        START_AT[$i]=$(echo "$info" | jq -r '.status.operationState.startedAt // empty')
                        [ -z "${START_AT[$i]}" ] && START_AT[$i]=$(now_iso)
                        END_AT[$i]=$(now_iso)
                    fi
                elif [ "$compare_status" = "diverged" ]; then
                    fail_out "$display: manifests history diverged from expected revision - change may not be deployed"
                fi
            fi
        fi

        # Phase 2: rollout detected — wait for Synced+Healthy.
        if [ "${STATE[$i]}" = "started" ]; then
            if [ "$sync_status" = "Synced" ] && [ "$health_status" = "Healthy" ]; then
                END_AT[$i]=$(now_iso)
                START_AT[$i]=$(echo "$info" | jq -r '.status.operationState.startedAt // empty')
                [ -z "${START_AT[$i]}" ] && START_AT[$i]=$(now_iso)
                VERIFIED_REV[$i]="$current_rev"
                STATE[$i]="done"
                echo "  ✓ $display became healthy at ${END_AT[$i]}"
            fi
        fi
    done

    [ "$ALL_DONE" = true ] && break
    TICK=$((TICK + 1))
    sleep "$POLL_INTERVAL"
done

# --- success: assemble aggregated output ------------------------------------

echo ""
echo "All applications synced and healthy."

RESULTS=()
for ((i = 0; i < N; i++)); do
    RESULTS+=("$(jq -cn \
        --arg name "${DISPLAY_NAMES[$i]}" \
        --arg app "${APP_NAMES[$i]}" \
        --arg revision "${VERIFIED_REV[$i]:-${EXPECTED_REVS[$i]}}" \
        --arg start "${START_AT[$i]}" \
        --arg end "${END_AT[$i]}" \
        --arg url "https://${ARGOCD_SERVER}/applications/argocd/${APP_NAMES[$i]}" \
        '{name: $name, app: $app, revision: $revision, start: $start, end: $end, status: "healthy", url: $url}')")
done

DEPLOYMENTS=$(printf '%s\n' "${RESULTS[@]}" | jq -s -c '.')

echo ""
echo "=========================================="
echo "Deployments verified: $N"
echo "$DEPLOYMENTS" | jq -r '.[] | "  \(.name): \(.start) -> \(.end)"'
echo "=========================================="

if [ -n "${GITHUB_OUTPUT:-}" ]; then
    echo "deployments=$DEPLOYMENTS" >> "$GITHUB_OUTPUT"
fi
echo "OUTPUT: deployments=$DEPLOYMENTS"
