#!/usr/bin/env bash
set -euo pipefail

# Local test script for argocd-wait-sync action
# This script simulates the GitHub Action locally for testing

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Load .env file if it exists
if [ -f "$SCRIPT_DIR/.env" ]; then
    echo "Loading environment from .env file..."
    set -a
    source "$SCRIPT_DIR/.env"
    set +a
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print error messages
error() {
    echo -e "${RED}ERROR: $1${NC}" >&2
}

# Function to print warning messages
warning() {
    echo -e "${YELLOW}WARNING: $1${NC}" >&2
}

# Function to print success messages
success() {
    echo -e "${GREEN}✓ $1${NC}"
}

# Usage information
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Test the ArgoCD wait-sync action locally.

Required Options:
  --server <url>           ArgoCD server URL (e.g., argocd.example.com)
  --app-name <name>        ArgoCD application name
  --auth-token <token>     ArgoCD authentication token
  --revision <sha>         Expected git revision/commit SHA

Optional Options:
  --timeout <seconds>      Timeout in seconds (default: 300)
  --help                   Show this help message

Prerequisites:
  - ArgoCD CLI must be installed (run ./install-cli.sh if needed)

Environment Variables (alternative to flags):
  ARGOCD_SERVER           Same as --server
  ARGOCD_APP_NAME         Same as --app-name
  ARGOCD_AUTH_TOKEN       Same as --auth-token
  ARGOCD_REVISION         Same as --revision
  ARGOCD_TIMEOUT          Same as --timeout

  Note: The script will automatically load .env file if it exists.
  Run ./setup-env.sh to create a .env file with your credentials.

Examples:
  # First-time setup (one time only)
  ./install-cli.sh           # Install ArgoCD CLI
  ./setup-env.sh             # Configure credentials in .env

  # Using command line arguments
  $0 --server argocd.example.com \\
     --app-name my-service-production \\
     --auth-token \$ARGOCD_TOKEN \\
     --revision abc123def

  # Using .env file (recommended)
  $0 --app-name my-service-production --revision abc123def

EOF
    exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --server)
            ARGOCD_SERVER="$2"
            shift 2
            ;;
        --app-name)
            ARGOCD_APP_NAME="$2"
            shift 2
            ;;
        --auth-token)
            ARGOCD_AUTH_TOKEN="$2"
            shift 2
            ;;
        --revision)
            ARGOCD_REVISION="$2"
            shift 2
            ;;
        --timeout)
            ARGOCD_TIMEOUT="$2"
            shift 2
            ;;
        --help)
            usage
            ;;
        *)
            error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Set defaults
ARGOCD_TIMEOUT="${ARGOCD_TIMEOUT:-300}"

# Validate required parameters
if [ -z "${ARGOCD_SERVER:-}" ]; then
    error "ArgoCD server is required (--server or ARGOCD_SERVER)"
    exit 1
fi

if [ -z "${ARGOCD_APP_NAME:-}" ]; then
    error "ArgoCD app name is required (--app-name or ARGOCD_APP_NAME)"
    exit 1
fi

if [ -z "${ARGOCD_AUTH_TOKEN:-}" ]; then
    error "ArgoCD auth token is required (--auth-token or ARGOCD_AUTH_TOKEN)"
    exit 1
fi

if [ -z "${ARGOCD_REVISION:-}" ]; then
    error "ArgoCD revision is required (--revision or ARGOCD_REVISION)"
    exit 1
fi

echo "=========================================="
echo "ArgoCD Wait-Sync Local Test"
echo "=========================================="
echo "Server:    $ARGOCD_SERVER"
echo "App Name:  $ARGOCD_APP_NAME"
echo "Timeout:   ${ARGOCD_TIMEOUT}s"
echo "Revision:  $ARGOCD_REVISION"
echo "=========================================="
echo ""

# Check for ArgoCD CLI
if ! command -v argocd &> /dev/null; then
    error "ArgoCD CLI is not installed"
    echo ""
    echo "Please install the ArgoCD CLI first:"
    echo "  ./install-cli.sh"
    echo ""
    exit 1
fi

echo "ArgoCD CLI: $(argocd version --client --short)"
echo ""

# Verify ArgoCD connection (no login needed - token passed directly)
export ARGOCD_SERVER
export ARGOCD_AUTH_TOKEN

echo "Verifying ArgoCD connection..."
if argocd app list --auth-token="$ARGOCD_AUTH_TOKEN" --server="$ARGOCD_SERVER" --grpc-web --insecure >/dev/null 2>&1; then
    success "Successfully connected to ArgoCD with token"
    echo ""
else
    error "Failed to connect to ArgoCD"
    echo ""
    echo "The token may be invalid or expired."
    echo "You can:"
    echo "  1. Generate a new token in ArgoCD UI (Settings > Accounts)"
    echo "  2. Login with SSO and re-run: argocd login $ARGOCD_SERVER --sso --grpc-web"
    echo "  3. Use test-with-existing-session.sh instead"
    echo ""
    exit 1
fi

# Run the wait-sync script
echo "Running wait-sync script..."
echo ""

# Export environment variables for the script
export ARGOCD_SERVER
export ARGOCD_AUTH_TOKEN
export APP_NAME="$ARGOCD_APP_NAME"
export EXPECTED_REVISION="$ARGOCD_REVISION"
export TIMEOUT="$ARGOCD_TIMEOUT"

# Run the shared script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
if "$SCRIPT_DIR/wait-sync.sh"; then
    success "Test completed successfully!"
else
    error "wait-sync.sh failed"
    exit 1
fi
