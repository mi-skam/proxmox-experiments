# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## Repository Overview

This repository contains documentation and guides for automating Proxmox VE infrastructure using a three-layer automation stack:

1. **Layer 0 (Optional)**: Ansible for Proxmox host installation (`lae.proxmox` role)
2. **Layer 1**: Terraform for VM provisioning and resource allocation
3. **Layer 2**: Cloud-init for OS initialization and base configuration
4. **Layer 3 (Optional)**: Ansible for complex software installation and day-2 operations

## Repository Structure

```
proxmox-experiments/
├── doc/                                    # Documentation articles
│   ├── proxmox-and-cloudinit.md           # German article on cloud-init
│   ├── proxmox-terraform-infrastructure.md # English article on Terraform
│   ├── proxmox-ansible-automation.md      # German article on Ansible
│   ├── infrastructure-repo-organization.md # Repository organization guide
│   └── sops-secrets-management.md         # SOPS secrets management guide
├── secrets/                                # SOPS-encrypted secrets (committed)
│   ├── common.sops.yaml                   # Shared secrets
│   └── *.sops.yaml                        # Environment-specific secrets
├── keys/                                   # Age private keys (gitignored)
│   └── *.age.key                          # Never commit these!
├── scripts/                                # Helper scripts
│   ├── sops-edit.sh                       # Edit encrypted secrets
│   └── rotate-keys.sh                     # Rotate age keys
└── LICENSE
```

## Key Concepts

### Tool Responsibilities

| Task | Terraform | Cloud-init | Ansible |
|------|:---------:|:----------:|:-------:|
| Create/destroy VMs | ✅ | - | ⚠️ |
| CPU/memory/disk allocation | ✅ | - | - |
| Network bridge assignment | ✅ | - | - |
| IP address configuration | ✅ | ✅ | - |
| User accounts & SSH keys | - | ✅ | ✅ |
| Base package installation | - | ✅ | ✅ |
| Complex software (k8s, etc.) | - | ⚠️ | ✅ |
| Multi-node coordination | - | - | ✅ |
| VM snapshots | - | - | ✅ |
| Install Proxmox itself | - | - | ✅ |

### Proxmox Provider Choice

**Use `bpg/proxmox` for new projects** (not `Telmate/proxmox`)
- Actively maintained
- Handles privilege separation correctly with newer Proxmox versions
- Better API compatibility

## Secrets Management with SOPS

This repository uses Mozilla SOPS with age encryption for unified secrets management across Terraform and Ansible.

### Common SOPS Commands

```bash
# Edit secrets (with validation)
./scripts/sops-edit.sh common
./scripts/sops-edit.sh dev

# Edit secrets directly
sops secrets/common.sops.yaml

# View decrypted secrets
sops -d secrets/common.sops.yaml

# View specific field
sops -d --extract '["proxmox"]["api_token_secret"]' secrets/common.sops.yaml

# Verify encryption
cat secrets/common.sops.yaml | grep "ENC\["
```

### Integration with Terraform

```hcl
# Load SOPS secrets
data "sops_file" "common_secrets" {
  source_file = "${path.module}/../../secrets/common.sops.yaml"
}

# Use in locals
locals {
  proxmox_token = data.sops_file.common_secrets.data["proxmox.api_token_secret"]
}
```

### Integration with Ansible

```yaml
# Use SOPS lookup in variables
proxmox_token_secret: "{{ lookup('community.sops.sops', '../secrets/common.sops.yaml', 'proxmox.api_token_secret') }}"
```

### Key Rotation

```bash
# Rotate age keys every 90 days
./scripts/rotate-keys.sh dev
./scripts/rotate-keys.sh prod
```

### Security Guidelines

✅ **Safe to commit:**
- `secrets/*.sops.yaml` (encrypted secrets)
- `.sops.yaml` (encryption configuration)
- `.sops.yaml.example` (template)

❌ **Never commit:**
- `keys/*.age.key` (private keys - gitignored)
- Decrypted secret files
- Age keys in any form

### Quick Setup

```bash
# 1. Install SOPS and age
brew install sops age  # macOS
sudo apt install age && wget <sops.deb>  # Ubuntu

# 2. Generate age key
age-keygen -o keys/dev.age.key

# 3. Configure SOPS with your public key
cp .sops.yaml.example .sops.yaml
# Edit .sops.yaml with your age public key

# 4. Set up SOPS to use your key
mkdir -p ~/.config/sops/age
cp keys/dev.age.key ~/.config/sops/age/keys.txt
chmod 600 ~/.config/sops/age/keys.txt

# 5. Create/edit secrets
sops secrets/common.sops.yaml
```

**See comprehensive guide:** [doc/sops-secrets-management.md](doc/sops-secrets-management.md)

## Common Commands

### Proxmox VM Management (via `qm` command)

```bash
# Create VM
qm create <vmid> --name <name> --memory <MB> --cores <num> --net0 virtio,bridge=vmbr0

# Import cloud image
qm importdisk <vmid> <image-file> local-lvm

# Configure VM
qm set <vmid> --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-<vmid>-disk-0
qm set <vmid> --ide2 local-lvm:cloudinit
qm set <vmid> --serial0 socket --vga serial0
qm set <vmid> --boot order=scsi0

# Convert to template
qm template <vmid>

# Configure cloud-init
qm set <vmid> --ciuser <username> --sshkeys <path>
qm set <vmid> --ipconfig0 ip=<ip>/<cidr>,gw=<gateway>

# Custom cloud-init files
qm set <vmid> --cicustom "user=local:snippets/userconfig.yaml,network=local:snippets/networkconfig.yaml"

# Debug cloud-init
qm cloudinit dump <vmid>
```

### Proxmox User/Permission Management (via `pveum` command)

```bash
# Create service account for Terraform
pveum user add terraform-prov@pve --password "<password>"

# Create role with required privileges
pveum role add TerraformProv -privs "Datastore.AllocateSpace Datastore.AllocateTemplate Datastore.Audit Pool.Allocate Pool.Audit Sys.Audit Sys.Console Sys.Modify VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.CPU VM.Config.Cloudinit VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Migrate VM.PowerMgmt SDN.Use"

# Create group and assign role
pveum group add terraform
pveum aclmod / -group terraform -role TerraformProv
pveum user modify terraform-prov@pve -groups terraform

# Create API token
pveum user token add terraform-prov@pve automation
```

### Terraform Workflow

```bash
# Initialize (download providers)
terraform init

# Upgrade providers
terraform init -upgrade

# Preview changes
terraform plan

# Apply changes
terraform apply

# Destroy infrastructure
terraform destroy

# Show outputs
terraform output
terraform output -json
```

### Ansible Workflow

```bash
# Install Ansible (Ubuntu)
sudo add-apt-repository ppa:ansible/ansible
sudo apt update
sudo apt install ansible python3-jmespath

# Install Ansible roles/collections
ansible-galaxy install -r requirements.yml
ansible-galaxy collection install community.sops

# Test connectivity
ansible -i hosts all -m ping

# Run playbook
ansible-playbook -i hosts playbook.yaml
```

## Documentation Language

The documentation articles are in both German and English:
- `proxmox-and-cloudinit.md`: German
- `proxmox-terraform-infrastructure.md`: English
- `proxmox-ansible-automation.md`: German
- `infrastructure-repo-organization.md`: English
- `sops-secrets-management.md`: English

When working with these files, preserve the original language of each document.

## Development Workflow

When implementing infrastructure automation in this pattern:

1. **Start with documentation**: Read relevant doc files for context
2. **Provider choice**: Use `bpg/proxmox` for Terraform
3. **Secrets management**: Use SOPS for all secrets (never plaintext `.tfvars`)
4. **Environment separation**: Use directory-based separation (`environments/dev`, `environments/prod`)
5. **Modules for reuse**: Extract into `modules/` when patterns repeat 3+ times
6. **Test with linked clones**: Save storage during development
7. **Key rotation**: Rotate age keys every 90 days using `./scripts/rotate-keys.sh`
