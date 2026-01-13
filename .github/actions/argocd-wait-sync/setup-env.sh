#!/usr/bin/env bash
set -euo pipefail

# Setup script for creating .env file with ArgoCD credentials

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "ArgoCD Test Environment Setup"
echo "=========================================="
echo ""

# Check if .env already exists
if [ -f .env ]; then
    echo -e "${YELLOW}Warning: .env file already exists${NC}"
    read -p "Do you want to overwrite it? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Setup cancelled. Using existing .env file."
        exit 0
    fi
fi

# Get ArgoCD server
read -p "ArgoCD server URL (e.g., argocd.monta.app): " ARGOCD_SERVER
if [ -z "$ARGOCD_SERVER" ]; then
    echo "Error: ArgoCD server is required"
    exit 1
fi

# Get ArgoCD token
echo ""
echo "ArgoCD authentication token:"
echo "  If you don't have one, generate it with:"
echo "    argocd login $ARGOCD_SERVER"
echo "    argocd account generate-token"
echo ""
read -p "ArgoCD token: " ARGOCD_AUTH_TOKEN
if [ -z "$ARGOCD_AUTH_TOKEN" ]; then
    echo "Error: ArgoCD token is required"
    exit 1
fi

# Optional: namespace
read -p "ArgoCD namespace (default: argocd): " ARGOCD_NAMESPACE
ARGOCD_NAMESPACE=${ARGOCD_NAMESPACE:-argocd}

# Optional: timeout
read -p "Default timeout in seconds (default: 300): " ARGOCD_TIMEOUT
ARGOCD_TIMEOUT=${ARGOCD_TIMEOUT:-300}

# Create .env file
cat > .env <<EOF
# ArgoCD Test Configuration
# Generated on $(date)

# ArgoCD server URL (without https://)
ARGOCD_SERVER=$ARGOCD_SERVER

# ArgoCD authentication token
ARGOCD_AUTH_TOKEN=$ARGOCD_AUTH_TOKEN

# ArgoCD namespace
ARGOCD_NAMESPACE=$ARGOCD_NAMESPACE

# Default timeout in seconds
ARGOCD_TIMEOUT=$ARGOCD_TIMEOUT
EOF

echo ""
echo -e "${GREEN}✓ .env file created successfully!${NC}"
echo ""
echo "You can now run tests with:"
echo "  source .env"
echo "  ./test-local.sh --app-name geo-production --revision d21aeca430231525cf69131c820db8d7ce6a9449"
echo ""
echo "Or simply:"
echo "  ./test-local.sh --app-name geo-production --revision d21aeca430231525cf69131c820db8d7ce6a9449"
echo "  (The script will automatically load .env if it exists)"
