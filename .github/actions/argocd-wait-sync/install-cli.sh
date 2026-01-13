#!/usr/bin/env bash
set -euo pipefail

# ArgoCD CLI Installation Script
# One-time setup to install the ArgoCD CLI

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

error() { echo -e "${RED}ERROR: $1${NC}" >&2; }
warning() { echo -e "${YELLOW}WARNING: $1${NC}" >&2; }
success() { echo -e "${GREEN}✓ $1${NC}"; }

echo "=========================================="
echo "ArgoCD CLI Installation"
echo "=========================================="
echo ""

# Check if already installed
if command -v argocd &> /dev/null; then
    CURRENT_VERSION=$(argocd version --client --short 2>/dev/null || echo "unknown")
    warning "ArgoCD CLI already installed: $CURRENT_VERSION"
    read -p "Reinstall? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Installation cancelled"
        exit 0
    fi
fi

# Detect OS and architecture
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)

case "$OS" in
    linux)
        ARGOCD_BINARY="argocd-linux-amd64"
        ;;
    darwin)
        if [ "$ARCH" = "arm64" ]; then
            ARGOCD_BINARY="argocd-darwin-arm64"
        else
            ARGOCD_BINARY="argocd-darwin-amd64"
        fi
        ;;
    *)
        error "Unsupported OS: $OS"
        echo "Supported platforms: Linux (amd64), macOS (amd64/arm64)"
        exit 1
        ;;
esac

echo "Detected platform: $OS ($ARCH)"
echo "Binary: $ARGOCD_BINARY"
echo ""

# Download
echo "Downloading latest ArgoCD CLI..."
if ! curl -sSL -o /tmp/argocd "https://github.com/argoproj/argo-cd/releases/latest/download/$ARGOCD_BINARY"; then
    error "Failed to download ArgoCD CLI"
    exit 1
fi

chmod +x /tmp/argocd

# Install
echo "Installing to /usr/local/bin/argocd (may require sudo password)..."
if sudo install -m 755 /tmp/argocd /usr/local/bin/argocd; then
    rm /tmp/argocd
    echo ""
    success "ArgoCD CLI installed successfully!"
    echo ""
    echo "Installed version: $(argocd version --client --short)"
    echo ""
    echo "Next steps:"
    echo "  1. Run ./setup-env.sh to configure credentials"
    echo "  2. Run ./test-local.sh to test the action"
else
    error "Failed to install ArgoCD CLI"
    rm /tmp/argocd
    exit 1
fi
