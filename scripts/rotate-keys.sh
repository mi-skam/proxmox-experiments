#!/usr/bin/env bash
# SOPS Age Key Rotation Script
# Automates the process of rotating age encryption keys
# Usage: ./scripts/rotate-keys.sh <environment>
# Example: ./scripts/rotate-keys.sh dev

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_error() {
    echo -e "${RED}ERROR:${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_info() {
    echo -e "${YELLOW}→${NC} $1"
}

log_step() {
    echo -e "${BLUE}[$1/6]${NC} $2"
}

# Validate arguments
if [ $# -eq 0 ]; then
    log_error "Missing environment argument"
    echo ""
    echo "Usage: $0 <environment>"
    echo ""
    echo "Available environments:"
    echo "  dev      - Development environment"
    echo "  staging  - Staging environment"
    echo "  prod     - Production environment"
    echo ""
    echo "Example: $0 dev"
    exit 1
fi

ENV="$1"

# Validate environment
case "$ENV" in
    dev|staging|prod)
        ;;
    *)
        log_error "Invalid environment: $ENV"
        echo "Valid environments: dev, staging, prod"
        exit 1
        ;;
esac

OLD_KEY="keys/${ENV}.age.key"
NEW_KEY="keys/${ENV}-new.age.key"
BACKUP_DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_KEY="keys/${ENV}.age.key.backup-${BACKUP_DATE}"

# Check prerequisites
if ! command -v age-keygen &> /dev/null; then
    log_error "age-keygen not found"
    echo "Install with: brew install age (macOS) or apt install age (Ubuntu)"
    exit 1
fi

if ! command -v sops &> /dev/null; then
    log_error "sops not found"
    echo "Install with: brew install sops (macOS) or see https://github.com/mozilla/sops"
    exit 1
fi

# Check if old key exists
if [ ! -f "$OLD_KEY" ]; then
    log_error "Old key not found: $OLD_KEY"
    echo "Generate initial key with: age-keygen -o $OLD_KEY"
    exit 1
fi

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  SOPS Age Key Rotation - $ENV environment"
echo "═══════════════════════════════════════════════════════════"
echo ""

# Step 1: Generate new key
log_step 1 "Generating new age key..."
age-keygen -o "$NEW_KEY" 2>/dev/null

# Extract public keys
OLD_PUBLIC=$(age-keygen -y "$OLD_KEY" 2>/dev/null)
NEW_PUBLIC=$(age-keygen -y "$NEW_KEY" 2>/dev/null)

log_success "New key generated: $NEW_KEY"
echo ""
echo "  Old public key: $OLD_PUBLIC"
echo "  New public key: $NEW_PUBLIC"
echo ""

# Step 2: Update .sops.yaml
log_step 2 "Update .sops.yaml configuration"
echo ""
echo "Add the NEW public key to .sops.yaml for the $ENV environment."
echo "Keep BOTH keys temporarily (old + new) until rotation is complete."
echo ""
echo "Example .sops.yaml entry:"
echo ""
echo "  - path_regex: secrets/${ENV}\\.sops\\.yaml$"
echo "    age: >-"
echo "      $OLD_PUBLIC,"
echo "      $NEW_PUBLIC"
echo ""
read -p "Press ENTER after updating .sops.yaml..."

# Verify .sops.yaml was updated
if ! grep -q "$NEW_PUBLIC" .sops.yaml; then
    log_error ".sops.yaml does not contain the new public key"
    echo "Add the new public key and try again"
    rm "$NEW_KEY"
    exit 1
fi

log_success ".sops.yaml updated with new key"

# Step 3: Re-encrypt secrets with both keys
log_step 3 "Re-encrypting secrets with both keys..."
echo ""

SECRET_FILES=(
    "secrets/common.sops.yaml"
    "secrets/${ENV}.sops.yaml"
)

for secret_file in "${SECRET_FILES[@]}"; do
    if [ -f "$secret_file" ]; then
        log_info "Re-encrypting $secret_file..."

        # Use old key to decrypt and re-encrypt with both keys
        SOPS_AGE_KEY=$(cat "$OLD_KEY") sops updatekeys "$secret_file" || {
            log_error "Failed to re-encrypt $secret_file"
            exit 1
        }

        log_success "Re-encrypted $secret_file"
    fi
done

echo ""

# Step 4: Test decryption with new key
log_step 4 "Testing decryption with new key..."
echo ""

for secret_file in "${SECRET_FILES[@]}"; do
    if [ -f "$secret_file" ]; then
        log_info "Testing $secret_file..."

        if SOPS_AGE_KEY=$(cat "$NEW_KEY") sops -d "$secret_file" > /dev/null 2>&1; then
            log_success "Can decrypt $secret_file with new key"
        else
            log_error "Cannot decrypt $secret_file with new key"
            echo "Rotation failed - old key still active"
            exit 1
        fi
    fi
done

echo ""

# Step 5: Remove old key from .sops.yaml
log_step 5 "Remove old key from .sops.yaml"
echo ""
echo "Now remove the OLD public key from .sops.yaml:"
echo "  Remove: $OLD_PUBLIC"
echo "  Keep:   $NEW_PUBLIC"
echo ""
read -p "Press ENTER after removing the old key from .sops.yaml..."

# Verify old key was removed
if grep -q "$OLD_PUBLIC" .sops.yaml; then
    log_error ".sops.yaml still contains the old public key"
    echo "Remove it and try again"
    exit 1
fi

log_success "Old key removed from .sops.yaml"

# Re-encrypt again with only new key
log_info "Re-encrypting with new key only..."
for secret_file in "${SECRET_FILES[@]}"; do
    if [ -f "$secret_file" ]; then
        SOPS_AGE_KEY=$(cat "$NEW_KEY") sops updatekeys "$secret_file" || {
            log_error "Failed final re-encryption of $secret_file"
            exit 1
        }
    fi
done

log_success "Secrets now use only the new key"

# Step 6: Backup old key and activate new key
log_step 6 "Activating new key..."
echo ""

mv "$OLD_KEY" "$BACKUP_KEY"
log_success "Old key backed up to: $BACKUP_KEY"

mv "$NEW_KEY" "$OLD_KEY"
log_success "New key activated: $OLD_KEY"

# Update default SOPS location if it exists
SOPS_KEY_FILE="$HOME/.config/sops/age/keys.txt"
if [ -f "$SOPS_KEY_FILE" ]; then
    log_info "Updating $SOPS_KEY_FILE..."

    # Backup current keys.txt
    cp "$SOPS_KEY_FILE" "$SOPS_KEY_FILE.backup-${BACKUP_DATE}"

    # Replace or append new key (naive approach - just append)
    cat "$OLD_KEY" >> "$SOPS_KEY_FILE"
    chmod 600 "$SOPS_KEY_FILE"

    log_success "Updated $SOPS_KEY_FILE (old version backed up)"
    echo ""
    echo "NOTE: You may have multiple keys in keys.txt now."
    echo "Review and remove old keys manually if needed:"
    echo "  $SOPS_KEY_FILE"
fi

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  ✓ Key Rotation Complete"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "Summary:"
echo "  • New key:    $OLD_KEY"
echo "  • Backup:     $BACKUP_KEY"
echo "  • Environment: $ENV"
echo ""
echo "Next steps:"
echo "  1. Test decryption: sops -d secrets/${ENV}.sops.yaml"
echo "  2. Commit updated .sops.yaml and secrets/"
echo "  3. Share new public key with team: age-keygen -y $OLD_KEY"
echo "  4. After 30 days, delete backup: rm $BACKUP_KEY"
echo ""
log_success "Rotation successful!"
