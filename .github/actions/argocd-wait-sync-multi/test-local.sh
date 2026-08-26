#!/usr/bin/env bash
set -euo pipefail

# Local test harness for the argocd-wait-sync-multi action — runs the real
# wait-sync-multi.sh against a live ArgoCD server. Loads .env if present (same
# convention as the sibling argocd-wait-sync action; reuse its ./install-cli.sh
# and ./setup-env.sh to install the CLI and store credentials).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$SCRIPT_DIR/.env" ]; then
    echo "Loading environment from .env..."
    set -a; source "$SCRIPT_DIR/.env"; set +a
fi

RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
error() { echo -e "${RED}ERROR: $1${NC}" >&2; }
success() { echo -e "${GREEN}✓ $1${NC}"; }

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Test the multi-app ArgoCD wait against a live server.

Required:
  --server <url>          ArgoCD server URL (or ARGOCD_SERVER)
  --auth-token <token>    ArgoCD token (or ARGOCD_AUTH_TOKEN)
  --apps '<json>'         JSON array: [{"app":..,"revision":..,"name":..}]

Optional:
  --source-repo <substr>  Match revisions[] source repoURL substring (multi-source apps)
  --manifest-repo <o/r>   Repo for supersede detection (default monta-app/kube-manifests)
  --timeout <seconds>     Overall timeout (default 900)
  --poll-interval <s>     Poll interval (default 5)
  --github-token <tok>    Token for supersede compare (or GITHUB_TOKEN / gh auth)
  --help

Prereqs: ArgoCD CLI installed (../argocd-wait-sync/install-cli.sh).
EOF
    exit 0
}

APPS_JSON="${APPS_JSON:-}"
SOURCE_REPO="${SOURCE_REPO:-}"
MANIFEST_REPO="${MANIFEST_REPO:-monta-app/kube-manifests}"
TIMEOUT="${TIMEOUT:-900}"
POLL_INTERVAL="${POLL_INTERVAL:-5}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --server) ARGOCD_SERVER="$2"; shift 2;;
        --auth-token) ARGOCD_AUTH_TOKEN="$2"; shift 2;;
        --apps) APPS_JSON="$2"; shift 2;;
        --source-repo) SOURCE_REPO="$2"; shift 2;;
        --manifest-repo) MANIFEST_REPO="$2"; shift 2;;
        --timeout) TIMEOUT="$2"; shift 2;;
        --poll-interval) POLL_INTERVAL="$2"; shift 2;;
        --github-token) GITHUB_TOKEN="$2"; shift 2;;
        --help) usage;;
        *) error "Unknown option: $1"; exit 1;;
    esac
done

: "${ARGOCD_SERVER:?--server or ARGOCD_SERVER required}"
: "${ARGOCD_AUTH_TOKEN:?--auth-token or ARGOCD_AUTH_TOKEN required}"
: "${APPS_JSON:?--apps required}"
: "${GITHUB_TOKEN:=$(gh auth token 2>/dev/null || true)}"

if ! command -v argocd >/dev/null 2>&1; then
    error "ArgoCD CLI not installed — run ../argocd-wait-sync/install-cli.sh"
    exit 1
fi

echo "Server: $ARGOCD_SERVER"
echo "Apps:   $(echo "$APPS_JSON" | jq -c '[.[].app]')"
echo "Source repo: ${SOURCE_REPO:-(singular revision)}"
echo ""

export ARGOCD_SERVER ARGOCD_AUTH_TOKEN APPS_JSON SOURCE_REPO MANIFEST_REPO TIMEOUT POLL_INTERVAL GITHUB_TOKEN

if "$SCRIPT_DIR/wait-sync-multi.sh"; then
    success "All apps verified healthy"
else
    error "wait-sync-multi.sh failed"
    exit 1
fi
