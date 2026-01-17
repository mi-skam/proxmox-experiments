# SOPS Secrets Management for Proxmox Infrastructure

Complete guide to managing secrets in Proxmox infrastructure automation using Mozilla SOPS (Secrets OPerationS) with age encryption.

## Table of Contents

1. [Introduction](#introduction)
2. [Why SOPS for Proxmox?](#why-sops-for-proxmox)
3. [Installation](#installation)
4. [Quick Start (5 Minutes)](#quick-start-5-minutes)
5. [Architecture](#architecture)
6. [Daily Workflows](#daily-workflows)
7. [Terraform Integration](#terraform-integration)
8. [Ansible Integration](#ansible-integration)
9. [Key Management](#key-management)
10. [Migration from .tfvars](#migration-from-tfvars)
11. [Troubleshooting](#troubleshooting)
12. [Security Best Practices](#security-best-practices)

---

## Introduction

SOPS (Secrets OPerationS) is a Mozilla tool for managing encrypted secrets in version control. This guide covers using SOPS with **age encryption** (simple, file-based keys) for Proxmox infrastructure automation.

### What SOPS Solves

| Problem | Without SOPS | With SOPS |
|---------|--------------|-----------|
| Secrets in git | ❌ Must gitignore (no version control) | ✅ Encrypted files can be committed |
| Terraform secrets | 🟡 Plaintext `.tfvars` files | ✅ Encrypted `.sops.yaml` |
| Ansible secrets | 🟡 ansible-vault (separate system) | ✅ Unified with Terraform |
| Secret rotation | ❌ Manual, no audit trail | ✅ Git history shows all changes |
| Team access | 🟡 Share plaintext files securely | ✅ Multi-key encryption |
| Partial encryption | ❌ Encrypt entire file | ✅ Selective field encryption |

---

## Why SOPS for Proxmox?

### Traditional Approach (Before SOPS)

```bash
# Terraform secrets (gitignored, plaintext on disk)
$ cat terraform.tfvars
proxmox_token = "terraform-prov@pve!automation=79f1a87e-3d4f-4feb-9350-e7758fabd173"

# Ansible secrets (encrypted but separate system)
$ ansible-vault view group_vars/vault.yml
proxmox_token_secret: "79f1a87e-3d4f-4feb-9350-e7758fabd173"

# Problems:
# - Two separate secret systems
# - No version control for Terraform secrets
# - Manual synchronization between tools
# - No partial encryption (entire file or nothing)
```

### SOPS Approach (Unified)

```yaml
# secrets/common.sops.yaml (committed to git, encrypted)
proxmox:
  api_url: https://10.0.1.241:8006          # Visible
  api_user: terraform-prov@pve               # Visible
  api_token_secret: ENC[AES256_GCM,data:...] # Encrypted

# Benefits:
# - Single source of truth
# - Version controlled
# - Works with both Terraform and Ansible
# - Only sensitive fields encrypted
```

---

## Installation

### macOS

```bash
# Install SOPS and age
brew install sops age

# Verify installation
sops --version
age --version
```

### Ubuntu/Debian

```bash
# Install age
sudo apt update
sudo apt install age

# Install SOPS
wget https://github.com/mozilla/sops/releases/download/v3.8.1/sops_3.8.1_amd64.deb
sudo dpkg -i sops_3.8.1_amd64.deb

# Verify installation
sops --version
age --version
```

### Other Linux Distributions

```bash
# Install age from package manager or binary
# Fedora/RHEL: sudo dnf install age
# Arch: sudo pacman -S age

# Install SOPS binary
wget https://github.com/mozilla/sops/releases/download/v3.8.1/sops-v3.8.1.linux.amd64
sudo mv sops-v3.8.1.linux.amd64 /usr/local/bin/sops
sudo chmod +x /usr/local/bin/sops
```

---

## Quick Start (5 Minutes)

### Step 1: Generate Age Key

```bash
# Create keys directory
mkdir -p keys

# Generate age encryption key
age-keygen -o keys/dev.age.key

# Output shows your public key (save this!):
# Public key: age1qyqszqgpqyqszqgpqyqszqgpqyqszqgpqyqszqgpqyqszqgpqyqszhdeqd
```

### Step 2: Configure SOPS

```bash
# Copy example configuration
cp .sops.yaml.example .sops.yaml

# Edit .sops.yaml and replace placeholder with your public key
# (the age1... string from step 1)
vim .sops.yaml
```

### Step 3: Set Up Age Key for SOPS

```bash
# Copy private key to SOPS default location
mkdir -p ~/.config/sops/age
cp keys/dev.age.key ~/.config/sops/age/keys.txt
chmod 600 ~/.config/sops/age/keys.txt
```

### Step 4: Create Your First Secret

```bash
# Create and edit common secrets file
sops secrets/common.sops.yaml
```

Your editor opens. Add secrets:

```yaml
proxmox:
  api_url: https://10.0.1.241:8006
  api_user: terraform-prov@pve
  api_token_id: automation
  api_token_secret: "79f1a87e-3d4f-4feb-9350-e7758fabd173"
  node_name: pve
  tls_insecure: true

vm_defaults:
  user: admin
  password: "ChangeMe123!"
```

Save and exit. SOPS automatically encrypts it.

### Step 5: Verify Encryption

```bash
# View encrypted file (only sensitive fields encrypted)
cat secrets/common.sops.yaml

# Output:
# proxmox:
#   api_url: https://10.0.1.241:8006  # Not encrypted
#   api_token_secret: ENC[AES256_GCM,data:abc123...,tag:xyz789...,type:str]  # Encrypted!

# Decrypt to view plaintext
sops -d secrets/common.sops.yaml
```

### Step 6: Commit to Git (Safe!)

```bash
git add secrets/common.sops.yaml .sops.yaml
git commit -m "Add encrypted Proxmox secrets"
git push

# Your secrets are encrypted at rest in the repository!
```

---

## Architecture

### Directory Structure

```
proxmox-experiments/
├── .sops.yaml                      # SOPS config (encryption rules)
├── .gitignore                      # Updated for SOPS patterns
│
├── secrets/                        # Encrypted secrets
│   ├── README.md
│   ├── .gitattributes             # Git diff config
│   ├── common.sops.yaml           # Shared secrets (✅ commit)
│   ├── dev.sops.yaml              # Dev environment (✅ commit)
│   ├── staging.sops.yaml          # Staging environment (✅ commit)
│   └── prod.sops.yaml             # Production environment (✅ commit)
│
├── keys/                           # Age private keys
│   ├── .gitignore                 # Ignore *.age.key files
│   ├── README.md
│   ├── dev.age.key                # Dev private key (❌ never commit)
│   └── prod.age.key               # Prod private key (❌ never commit)
│
└── scripts/                        # Helper scripts
    ├── sops-edit.sh               # Edit secrets wrapper
    └── rotate-keys.sh             # Key rotation automation
```

### Secret File Structure

Each SOPS-encrypted file has this structure:

```yaml
# ===== Unencrypted Section (Visible in Git) =====
proxmox:
  api_url: https://10.0.1.241:8006  # Not sensitive
  api_user: terraform-prov@pve       # Not sensitive
  api_token_id: automation           # Not sensitive
  
  # ===== Encrypted Fields =====
  api_token_secret: ENC[AES256_GCM,data:KmCzYxPj7V...,tag:n8F2k...,type:str]
  
vm_defaults:
  user: admin                        # Not encrypted
  password: ENC[AES256_GCM,data:...]  # Encrypted

# ===== SOPS Metadata (Auto-Managed) =====
sops:
  age:
    - recipient: age1qyqszqgpqyqszqgpqyqszqgpqyqszqgpqyqszqgpqyqszqgpqyqszhdeqd
      enc: |
        -----BEGIN AGE ENCRYPTED FILE-----
        YWdlLWVuY3J5cHRpb24ub3JnL3YxCi0+IFgyNTUxOSBLV0kvRGtXV3NiQ1ByOTZp
        ...
        -----END AGE ENCRYPTED FILE-----
  lastmodified: "2026-01-17T18:00:00Z"
  mac: ENC[AES256_GCM,data:FLjMQ+==,tag:PJ7yg==,type:str]
  version: 3.8.1
```

### .sops.yaml Configuration

The `.sops.yaml` file defines encryption rules:

```yaml
creation_rules:
  # Common secrets
  - path_regex: secrets/common\.sops\.yaml$
    age: age1your_public_key_here
    encrypted_regex: '^(proxmox_api_token|api_token_secret|password|private_key|token|secret)$'
```

**Key directives:**
- `path_regex`: Which files this rule applies to
- `age`: Public key(s) that can decrypt (comma-separated for multiple)
- `encrypted_regex`: Only encrypt fields matching this pattern

---

## Daily Workflows

### Editing Secrets

**Using the helper script (recommended):**

```bash
./scripts/sops-edit.sh common
```

**Using SOPS directly:**

```bash
sops secrets/common.sops.yaml
```

Your `$EDITOR` opens with decrypted content. Edit, save, and SOPS re-encrypts automatically.

### Viewing Decrypted Secrets

```bash
# Entire file
sops -d secrets/common.sops.yaml

# Specific field
sops -d --extract '["proxmox"]["api_token_secret"]' secrets/common.sops.yaml

# Output as JSON
sops -d --output-type json secrets/common.sops.yaml
```

### Adding New Secrets

```bash
# Edit existing file and add new fields
sops secrets/common.sops.yaml

# Or create new environment
sops secrets/staging.sops.yaml
```

### Verifying Encryption

```bash
# Check that sensitive fields are encrypted
cat secrets/common.sops.yaml | grep "ENC\["

# Should output lines like:
#   api_token_secret: ENC[AES256_GCM,data:...,tag:...,type:str]
```

### Committing Changes

```bash
# Add encrypted files (safe!)
git add secrets/common.sops.yaml
git commit -m "Update Proxmox API token"
git push

# Git history shows who changed what and when
git log -p secrets/common.sops.yaml
```

---

## Terraform Integration

### Method: carlpett/sops Provider

The `carlpett/sops` Terraform provider reads SOPS-encrypted files.

### Setup

**1. Install Provider**

```hcl
# environments/dev/providers.tf
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.38.0"
    }
    
    sops = {
      source  = "carlpett/sops"
      version = "~> 1.0"
    }
  }
}

provider "sops" {
  # Automatically uses:
  # - SOPS_AGE_KEY environment variable, or
  # - ~/.config/sops/age/keys.txt
}
```

**2. Load Secrets**

```hcl
# environments/dev/secrets.tf
data "sops_file" "common_secrets" {
  source_file = "${path.module}/../../secrets/common.sops.yaml"
}

data "sops_file" "env_secrets" {
  source_file = "${path.module}/../../secrets/dev.sops.yaml"
}

# Access secrets via locals
locals {
  proxmox_api_url    = data.sops_file.common_secrets.data["proxmox.api_url"]
  proxmox_api_token  = data.sops_file.common_secrets.data["proxmox.api_token_secret"]
  proxmox_node       = data.sops_file.common_secrets.data["proxmox.node_name"]
  vm_user            = data.sops_file.common_secrets.data["vm_defaults.user"]
  vm_password        = data.sops_file.common_secrets.data["vm_defaults.password"]
  network_gateway    = data.sops_file.env_secrets.data["vms.network.gateway"]
}
```

**3. Use in Resources**

```hcl
# environments/dev/providers.tf
provider "proxmox" {
  endpoint  = local.proxmox_api_url
  insecure  = true
  
  api_token = "${data.sops_file.common_secrets.data["proxmox.api_user"]}!${data.sops_file.common_secrets.data["proxmox.api_token_id"]}=${local.proxmox_api_token}"
}

# environments/dev/vms.tf
resource "proxmox_virtual_environment_vm" "kubernetes_node" {
  name      = "k8s-worker-01"
  node_name = local.proxmox_node
  
  initialization {
    user_account {
      username = local.vm_user
      password = local.vm_password
    }
    
    ip_config {
      ipv4 {
        address = "10.0.50.11/24"
        gateway = local.network_gateway
      }
    }
  }
}
```

### Workflow

```bash
# Navigate to environment directory
cd environments/dev

# Initialize (downloads SOPS provider)
terraform init

# Plan (SOPS automatically decrypts secrets)
terraform plan

# Apply
terraform apply

# Secrets are decrypted in-memory only, never written to disk
```

---

## Ansible Integration

### Method: community.sops Collection

The `community.sops` Ansible collection provides a lookup plugin for SOPS files.

### Setup

**1. Install Collection**

```yaml
# ansible/requirements.yml
---
collections:
  - name: community.sops
    version: ">=1.6.0"
  - name: community.proxmox
    version: ">=1.0.0"
```

```bash
ansible-galaxy collection install -r requirements.yml
```

**2. Enable SOPS Plugin**

```ini
# ansible/ansible.cfg
[defaults]
inventory = hosts
vars_plugins_enabled = community.sops.sops
```

**3. Use in Variables**

```yaml
# ansible/group_vars/all.yml
---
# SOPS lookup: reads from encrypted file
proxmox_host: "{{ lookup('community.sops.sops', '../secrets/common.sops.yaml', 'proxmox.api_url') | regex_replace('https://', '') | regex_replace(':8006', '') }}"
proxmox_user: "{{ lookup('community.sops.sops', '../secrets/common.sops.yaml', 'proxmox.api_user') }}"
proxmox_token_id: "{{ lookup('community.sops.sops', '../secrets/common.sops.yaml', 'proxmox.api_token_id') }}"
proxmox_token_secret: "{{ lookup('community.sops.sops', '../secrets/common.sops.yaml', 'proxmox.api_token_secret') }}"

vm_default_user: "{{ lookup('community.sops.sops', '../secrets/common.sops.yaml', 'vm_defaults.user') }}"
vm_default_password: "{{ lookup('community.sops.sops', '../secrets/common.sops.yaml', 'vm_defaults.password') }}"
```

**4. Use in Playbooks**

```yaml
# ansible/playbooks/proxmox_snapshot.yml
---
- name: Create VM snapshots
  hosts: localhost
  gather_facts: false
  
  tasks:
    - name: Create snapshot for VM
      community.proxmox.proxmox_kvm:
        api_host: "{{ proxmox_host }}"
        api_user: "{{ proxmox_user }}"
        api_token_id: "{{ proxmox_token_id }}"
        api_token_secret: "{{ proxmox_token_secret }}"
        vmid: 100
        state: snapshot
        snapname: "backup-{{ ansible_date_time.iso8601_basic_short }}"
```

### Workflow

```bash
# Navigate to Ansible directory
cd ansible

# Run playbook (SOPS decrypts automatically)
ansible-playbook playbooks/proxmox_snapshot.yml

# Secrets decrypted in-memory only
```

---

## Key Management

### Generating Keys

```bash
# Generate age key for an environment
age-keygen -o keys/dev.age.key

# Output shows:
# Public key: age1abc123...
# (Save this public key for .sops.yaml)
```

### Per-Environment Keys

Best practice: Use different keys for different environments.

```bash
# Generate separate keys
age-keygen -o keys/dev.age.key
age-keygen -o keys/staging.age.key
age-keygen -o keys/prod.age.key

# Extract public keys
age-keygen -y keys/dev.age.key      # age1abc123...
age-keygen -y keys/staging.age.key  # age1def456...
age-keygen -y keys/prod.age.key     # age1ghi789...

# Update .sops.yaml with respective public keys
```

### Rotating Keys

Rotate keys every 90 days for security.

**Using the helper script:**

```bash
./scripts/rotate-keys.sh dev
```

**Manual rotation:**

```bash
# 1. Generate new key
age-keygen -o keys/dev-new.age.key
NEW_PUBLIC=$(age-keygen -y keys/dev-new.age.key)

# 2. Update .sops.yaml - add new key alongside old key temporarily
# 3. Re-encrypt secrets with both keys
SOPS_AGE_KEY=$(cat keys/dev.age.key) sops updatekeys secrets/common.sops.yaml
SOPS_AGE_KEY=$(cat keys/dev.age.key) sops updatekeys secrets/dev.sops.yaml

# 4. Test decryption with new key
SOPS_AGE_KEY=$(cat keys/dev-new.age.key) sops -d secrets/common.sops.yaml

# 5. Remove old key from .sops.yaml
# 6. Re-encrypt with new key only
SOPS_AGE_KEY=$(cat keys/dev-new.age.key) sops updatekeys secrets/common.sops.yaml

# 7. Backup old key and activate new one
mv keys/dev.age.key keys/dev.age.key.backup-$(date +%Y%m%d)
mv keys/dev-new.age.key keys/dev.age.key
```

### Sharing Keys with Team

When adding a team member:

```bash
# 1. Team member generates their own key
age-keygen -o ~/.config/sops/age/keys.txt
age-keygen -y ~/.config/sops/age/keys.txt  # Share public key only

# 2. Add their public key to .sops.yaml (comma-separated)
- path_regex: secrets/common\.sops\.yaml$
  age: >-
    age1your_key,
    age1team_member_key
  encrypted_regex: '^(proxmox_api_token|api_token_secret|password|private_key|token|secret)$'

# 3. Re-encrypt secrets so both keys can decrypt
sops updatekeys secrets/common.sops.yaml

# 4. Team member can now decrypt
sops -d secrets/common.sops.yaml
```

### Key Storage

**Development:**
- Store in `~/.config/sops/age/keys.txt` (SOPS default)
- Backup in password manager (1Password, Bitwarden, etc.)

**Production:**
- Separate key, restricted access
- Hardware security module (HSM) for enterprise
- Encrypted USB drive in secure location for small teams

---

## Migration from .tfvars

Transitioning from traditional `.tfvars` files to SOPS.

### Before (Traditional Approach)

```hcl
# terraform.tfvars (gitignored, plaintext)
proxmox_api_url          = "https://10.0.1.241:8006"
proxmox_api_token_id     = "terraform-prov@pve!automation"
proxmox_api_token_secret = "79f1a87e-3d4f-4feb-9350-e7758fabd173"
proxmox_node             = "pve"
```

### After (SOPS Approach)

**1. Create SOPS secret file:**

```yaml
# secrets/common.sops.yaml (committed, encrypted)
proxmox:
  api_url: https://10.0.1.241:8006
  api_user: terraform-prov@pve
  api_token_id: automation
  api_token_secret: "79f1a87e-3d4f-4feb-9350-e7758fabd173"  # Encrypted
  node_name: pve
```

**2. Update Terraform to use SOPS:**

```hcl
# Add sops provider (see Terraform Integration section)
data "sops_file" "common_secrets" {
  source_file = "${path.module}/../../secrets/common.sops.yaml"
}

locals {
  proxmox_api_url    = data.sops_file.common_secrets.data["proxmox.api_url"]
  proxmox_api_token  = data.sops_file.common_secrets.data["proxmox.api_token_secret"]
  # ...
}
```

**3. Remove old .tfvars:**

```bash
# Backup first
cp terraform.tfvars terraform.tfvars.backup

# Remove from working directory
rm terraform.tfvars

# Keep .tfvars.example for documentation
```

### Migration Timeline

**Week 1: Setup**
- Install SOPS and age
- Generate age keys
- Create `.sops.yaml`
- Create `secrets/common.sops.yaml` with dummy data
- Test encryption/decryption

**Week 2: Terraform Migration**
- Add `carlpett/sops` provider
- Create `secrets.tf` data sources
- Migrate one secret as proof-of-concept
- Test `terraform plan` works

**Week 3: Full Migration**
- Migrate all secrets to SOPS files
- Update all Terraform configs
- Test deployments in dev environment

**Week 4: Cleanup**
- Remove old `.tfvars` files
- Update documentation
- Train team members

---

## Troubleshooting

### "no key could be found to decrypt"

**Cause:** SOPS can't find your age private key.

**Fix:**

```bash
# Check if key exists
ls -l ~/.config/sops/age/keys.txt

# Verify key format (should start with AGE-SECRET-KEY-)
head -n1 ~/.config/sops/age/keys.txt

# Extract public key from private key
age-keygen -y ~/.config/sops/age/keys.txt

# Compare with .sops.yaml to ensure they match
grep "age:" .sops.yaml
```

### "failed to get the data key"

**Cause:** Private key doesn't match public key in `.sops.yaml`.

**Fix:**

```bash
# Verify your public key
age-keygen -y keys/dev.age.key

# Check .sops.yaml has this public key
cat .sops.yaml

# If mismatch, update .sops.yaml and re-encrypt
sops updatekeys secrets/common.sops.yaml
```

### "MAC mismatch" Error

**Cause:** File was modified outside SOPS or is corrupted.

**Fix:**

```bash
# Try to decrypt (will show where corruption occurred)
sops -d secrets/common.sops.yaml

# If corrupted, restore from git history
git checkout HEAD^ secrets/common.sops.yaml

# Re-apply your changes
sops secrets/common.sops.yaml
```

### Terraform Can't Decrypt

**Problem:** `terraform plan` fails with SOPS error.

**Fix:**

```bash
# Test SOPS decryption manually first
sops -d secrets/common.sops.yaml

# Check Terraform provider is installed
terraform init

# Enable debug logging
export TF_LOG=DEBUG
terraform plan 2>&1 | grep -i sops

# Verify age key is accessible
ls -l ~/.config/sops/age/keys.txt
echo $SOPS_AGE_KEY
```

### Ansible Lookup Fails

**Problem:** Ansible can't find SOPS secrets.

**Fix:**

```bash
# Verify community.sops collection is installed
ansible-galaxy collection list | grep community.sops

# Test SOPS lookup directly
ansible localhost -m debug -a "msg={{ lookup('community.sops.sops', 'secrets/common.sops.yaml', 'proxmox.api_url') }}"

# Check file path (relative to playbook location)
# Ansible runs from playbook directory, not project root
```

---

## Security Best Practices

### 1. Key Separation

**DO:**
- Use separate keys for dev/staging/prod
- Restrict production key access to operations team only
- Store production keys separately from development keys

**DON'T:**
- Use the same key for all environments
- Share production keys with all developers
- Store all keys in the same location

### 2. Version Control

**DO:**
- Commit encrypted `.sops.yaml` files
- Use signed commits for secret changes
- Require PR reviews for secrets modifications

**DON'T:**
- Commit `.age.key` files (private keys)
- Commit decrypted `.yaml` files
- Force-push over secret history

### 3. Key Backup

**DO:**
- Back up keys in encrypted password manager
- Store production key backups offline (encrypted USB)
- Document key custodians (who has access)
- Test backup restoration regularly

**DON'T:**
- Store keys in unencrypted files
- Email or Slack private keys
- Store backup keys in the same location as primary

### 4. Secret Rotation

**DO:**
- Rotate age keys every 90 days
- Rotate secrets when team members leave
- Use different secrets for dev/staging/prod
- Document rotation schedule

**DON'T:**
- Reuse old secrets after rotation
- Use the same Proxmox API token across environments
- Skip rotation "because it's working"

### 5. Access Control

**DO:**
- Grant minimum necessary access (principle of least privilege)
- Use branch protection on secret files
- Audit who has decryption keys
- Remove access when team members leave

**DON'T:**
- Share age private keys via unencrypted channels
- Give everyone production access "just in case"
- Use a single shared key for the entire team

### 6. Monitoring

**DO:**
- Review git logs for secret changes: `git log -p secrets/`
- Set up alerts for secret file modifications
- Monitor who commits secret changes
- Review secret access regularly

**DON'T:**
- Ignore unexpected secret modifications
- Skip reviewing secret change PRs
- Allow automatic merges of secret changes

---

## Advanced Topics

### Multiple Keys in keys.txt

Store multiple age private keys in `~/.config/sops/age/keys.txt`:

```
# Dev key
AGE-SECRET-KEY-1ABC...

# Staging key
AGE-SECRET-KEY-1DEF...

# Shared infrastructure key
AGE-SECRET-KEY-1GHI...
```

SOPS tries all keys until one works.

### Git Diff for Encrypted Files

Show decrypted diff in git:

```bash
# Configure git diff filter
git config diff.sopsdiffer.textconv "sops -d"

# Already configured via secrets/.gitattributes
# Now git diff shows decrypted changes:
git diff secrets/common.sops.yaml
```

### Cloud-init Integration

Use SOPS secrets in cloud-init templates:

```yaml
# cloud-init/userdata.yaml.tpl (Terraform template)
#cloud-config
users:
  - name: ${vm_user}
    passwd: ${vm_password_hash}
    ssh_authorized_keys:
      - ${ssh_public_key}
```

```hcl
# Terraform
locals {
  vm_user = data.sops_file.common_secrets.data["vm_defaults.user"]
  vm_password = data.sops_file.common_secrets.data["vm_defaults.password"]
}

data "template_file" "user_data" {
  template = file("${path.module}/cloud-init/userdata.yaml.tpl")
  vars = {
    vm_user           = local.vm_user
    vm_password_hash  = bcrypt(local.vm_password)
    ssh_public_key    = file("~/.ssh/id_rsa.pub")
  }
}
```

---

## Summary

### Key Commands Reference

```bash
# Installation
brew install sops age  # macOS
sudo apt install age && wget <sops.deb> && dpkg -i <sops.deb>  # Ubuntu

# Key generation
age-keygen -o keys/dev.age.key
age-keygen -y keys/dev.age.key  # Extract public key

# Editing secrets
sops secrets/common.sops.yaml
./scripts/sops-edit.sh common

# Viewing secrets
sops -d secrets/common.sops.yaml
sops -d --extract '["proxmox"]["api_token_secret"]' secrets/common.sops.yaml

# Key rotation
./scripts/rotate-keys.sh dev
sops updatekeys secrets/common.sops.yaml

# Verification
cat secrets/common.sops.yaml | grep "ENC\["
```

### Decision Matrix

| Use Case | Tool Choice |
|----------|-------------|
| Proxmox lab (personal) | age keys ✅ |
| Small team (< 10 people) | age keys ✅ |
| Enterprise (> 10 people) | Consider cloud KMS |
| Offline infrastructure | age keys ✅ |
| Cloud-based infrastructure | age or cloud KMS |
| Compliance requirements | Evaluate cloud KMS |

### Benefits Recap

✅ **Encryption at rest** - Secrets encrypted in git  
✅ **Version control** - Track all changes with audit trail  
✅ **Unified secrets** - Single system for Terraform + Ansible  
✅ **Selective encryption** - Only sensitive fields encrypted  
✅ **Git-friendly** - Diffable metadata  
✅ **Team access** - Multi-key encryption support  
✅ **No cloud dependencies** - Works offline with age  

---

## See Also

- [Mozilla SOPS Documentation](https://github.com/mozilla/sops)
- [age Encryption Tool](https://github.com/FiloSottile/age)
- [carlpett/sops Terraform Provider](https://registry.terraform.io/providers/carlpett/sops)
- [community.sops Ansible Collection](https://docs.ansible.com/ansible/latest/collections/community/sops/)
- [Infrastructure Repository Organization](infrastructure-repo-organization.md)
- [Proxmox Terraform Guide](proxmox-terraform-infrastructure.md)
- [Proxmox Ansible Guide](proxmox-ansible-automation.md)
