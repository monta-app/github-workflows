#!/usr/bin/env bash
set -uo pipefail

# Offline tests for wait-sync-multi.sh. Drives the state machine via FIXTURE_DIR
# (no ArgoCD/network). Covers: multi-source revision extraction, two-phase
# progress->healthy, fail-fast on Degraded, and single-source backward compat.
#
# Not covered here (time-dependent — validate in the live run): supersede-ahead,
# diverged, ComparisonError>60s, Unknown>30s, overall timeout.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/../wait-sync-multi.sh"
FIX="$SCRIPT_DIR/fixtures"
R="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
PASS=0; FAIL=0
run() {
    local name="$1" expected_code="$2"; shift 2
    local out code
    out=$(env ARGOCD_SERVER=argocd.test ARGOCD_AUTH_TOKEN=x POLL_INTERVAL=0 "$@" bash "$SUT" 2>&1)
    code=$?
    if [ "$code" -eq "$expected_code" ]; then
        echo -e "${GREEN}✓${NC} $name (exit $code)"
        PASS=$((PASS + 1))
        LAST_OUT="$out"
    else
        echo -e "${RED}✗${NC} $name — expected exit $expected_code, got $code"
        echo "$out" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        LAST_OUT="$out"
    fi
}
assert_contains() {
    if echo "$LAST_OUT" | grep -qF "$1"; then
        echo -e "  ${GREEN}·${NC} output contains: $1"
    else
        echo -e "  ${RED}·${NC} output MISSING: $1"; FAIL=$((FAIL + 1))
    fi
}

echo "== wait-sync-multi.sh offline tests =="

# A: two dual-source apps already healthy at manifests revision R
run "A multi-source, both healthy" 0 \
    APPS_JSON="[{\"app\":\"frontend-hub-production\",\"revision\":\"$R\",\"name\":\"hub\"},{\"app\":\"portals-production\",\"revision\":\"$R\",\"name\":\"portals\"}]" \
    SOURCE_REPO=monorepo-typescript-manifests \
    FIXTURE_DIR="$FIX/a-multi-healthy"
assert_contains '"name":"hub"'
assert_contains '"status":"healthy"'
assert_contains 'Deployments verified: 2'

# B: single dual-source app, Progressing then Healthy across ticks
run "B progress -> healthy" 0 \
    APPS_JSON="[{\"app\":\"svc-production\",\"revision\":\"$R\",\"name\":\"svc\"}]" \
    SOURCE_REPO=monorepo-typescript-manifests \
    FIXTURE_DIR="$FIX/b-progress"
assert_contains 'rollout in progress'
assert_contains 'became healthy'

# C: degraded -> fail-fast (exit 1)
run "C degraded fail-fast" 1 \
    APPS_JSON="[{\"app\":\"bad-production\",\"revision\":\"$R\",\"name\":\"bad\"}]" \
    SOURCE_REPO=monorepo-typescript-manifests \
    FIXTURE_DIR="$FIX/c-degraded"
assert_contains 'health is Degraded'

# D: single-source app, SOURCE_REPO unset (singular .status.sync.revision)
run "D single-source backward compat" 0 \
    APPS_JSON="[{\"app\":\"geo-production\",\"revision\":\"$R\",\"name\":\"geo\"}]" \
    FIXTURE_DIR="$FIX/d-single"
assert_contains '"name":"geo"'

# E: invalid APPS_JSON -> validation error
run "E empty apps array rejected" 1 \
    APPS_JSON="[]" \
    FIXTURE_DIR="$FIX/d-single"
assert_contains 'non-empty JSON array'

echo ""
echo "Passed: $PASS  Failed: $FAIL"
[ "$FAIL" -eq 0 ]
