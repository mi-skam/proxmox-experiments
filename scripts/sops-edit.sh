#!/usr/bin/env bash
# SOPS Secret Editor
# Wrapper script for editing SOPS-encrypted secret files
# Usage: ./scripts/sops-edit.sh <environment>
# Example: ./scripts/sops-edit.sh common

set -euo pipefail

# Color output for better UX
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Print colored message
log_error() {
    echo -e "${RED}ERROR:${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_info() {
    echo -e "${YELLOW}→${NC} $1"
}

# Validate arguments
if [ $# -eq 0 ]; then
    log_error "Missing environment argument"
    echo ""
    echo "Usage: $0 <environment>"
    echo ""
    echo "Available environments:"
    echo "  common   - Shared secrets across all environments"
    echo "  dev      - Development environment secrets"
    echo "  staging  - Staging environment secrets"
    echo "  prod     - Production environment secrets"
    echo ""
    echo "Example: $0 common"
    exit 1
fi

ENV="$1"
SECRET_FILE="secrets/${ENV}.sops.yaml"

# Validate environment
case "$ENV" in
    common|dev|staging|prod)
        ;;
    *)
        log_error "Invalid environment: $ENV"
        echo "Valid environments: common, dev, staging, prod"
        exit 1
        ;;
esac

# Check if secret file exists
if [ ! -f "$SECRET_FILE" ]; then
    log_error "Secret file not found: $SECRET_FILE"
    echo ""
    echo "Create it first with:"
    echo "  sops $SECRET_FILE"
    exit 1
fi

# Check SOPS installation
if ! command -v sops &> /dev/null; then
    log_error "sops is not installed"
    echo ""
    echo "Install with:"
    echo "  macOS:         brew install sops"
    echo "  Ubuntu/Debian: wget https://github.com/mozilla/sops/releases/download/v3.8.1/sops_3.8.1_amd64.deb"
    echo "                 sudo dpkg -i sops_3.8.1_amd64.deb"
    exit 1
fi

# Check age installation
if ! command -v age &> /dev/null; then
    log_error "age is not installed (required for SOPS encryption)"
    echo ""
    echo "Install with:"
    echo "  macOS:         brew install age"
    echo "  Ubuntu/Debian: sudo apt install age"
    exit 1
fi

# Check age key configuration
AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"
if [ ! -f "$AGE_KEY_FILE" ] && [ -z "${SOPS_AGE_KEY:-}" ]; then
    log_error "Age key not configured"
    echo ""
    echo "Configure age key with one of these methods:"
    echo ""
    echo "Option 1 (Recommended): Copy key to default location"
    echo "  mkdir -p ~/.config/sops/age"
    echo "  cp keys/dev.age.key ~/.config/sops/age/keys.txt"
    echo "  chmod 600 ~/.config/sops/age/keys.txt"
    echo ""
    echo "Option 2: Export key as environment variable"
    echo "  export SOPS_AGE_KEY=\$(cat keys/dev.age.key)"
    echo ""
    echo "Don't have a key yet? Generate one:"
    echo "  age-keygen -o keys/dev.age.key"
    exit 1
fi

# Edit the secret file
log_info "Opening $SECRET_FILE in editor..."
sops "$SECRET_FILE"

# Verify encryption after edit
log_info "Verifying encryption..."
if grep -q "ENC\[" "$SECRET_FILE"; then
    log_success "Secret file encrypted successfully"
    log_success "Safe to commit: git add $SECRET_FILE"
else
    log_error "Warning: File does not appear to be encrypted!"
    log_error "Check .sops.yaml configuration"
    exit 1
fi
