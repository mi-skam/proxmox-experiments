# Organizing a Proxmox Infrastructure Repository

This guide explains how to structure an infrastructure repository for creating VMs on a Proxmox cluster using Terraform, cloud-init, and Ansible, with a practical example of a 3-node container orchestration test cluster.

## Table of Contents

1. [Requirements](#requirements)
2. [Key Decisions](#key-decisions)
3. [Tool Responsibilities](#tool-responsibilities)
4. [Repository Structure](#repository-structure)
5. [Shared vs Individual Configuration](#shared-vs-individual-configuration)
6. [Example: 3-Node Container Orchestration Cluster](#example-3-node-container-orchestration-cluster)
7. [Ansible Integration](#ansible-integration)

---

## Requirements

### Proxmox Host Requirements

| Requirement | Description |
|-------------|-------------|
| Proxmox VE 8.x+ | REST API and cloud-init support |
| API Token | Service account with appropriate permissions |
| Template VM | Pre-configured cloud-init enabled base image |
| Storage | `local-lvm` or similar for VM disks |
| Snippets storage | For custom cloud-init configurations |

### Development Machine Requirements

| Requirement | Description |
|-------------|-------------|
| Terraform 1.5+ | Infrastructure as Code tool |
| SSH Key Pair | For VM authentication |
| Network access | To Proxmox API (port 8006) |

### Proxmox Permission Setup

Create a dedicated service account with minimal required permissions:

```bash
# Variables
USERNAME="terraform-prov"
REALM="pve"
ROLE_NAME="TerraformProv"
GROUP_NAME="terraform"
TOKEN_NAME="automation"

# Create user
pveum user add "${USERNAME}@${REALM}" --password "secure-password"

# Create role with required privileges
pveum role add "${ROLE_NAME}" -privs "Datastore.AllocateSpace Datastore.AllocateTemplate Datastore.Audit Pool.Allocate Pool.Audit Sys.Audit Sys.Console Sys.Modify VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.CPU VM.Config.Cloudinit VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Migrate VM.PowerMgmt SDN.Use"

# Create group and assign role
pveum group add "${GROUP_NAME}"
pveum aclmod / -group "${GROUP_NAME}" -role "${ROLE_NAME}"
pveum user modify "${USERNAME}@${REALM}" -groups "${GROUP_NAME}"

# Create API token (save the output!)
pveum user token add "${USERNAME}@${REALM}" "${TOKEN_NAME}"
```

### Base Template Preparation

Before Terraform can provision VMs, you need a cloud-init enabled template:

```bash
# Variables
TEMPLATE_VMID="9000"
TEMPLATE_NAME="ubuntu-2404-base"
IMAGE_FILE="noble-server-cloudimg-amd64.img"
IMAGE_URL="https://cloud-images.ubuntu.com/noble/current/${IMAGE_FILE}"
STORAGE="local-lvm"
BRIDGE="vmbr0"
MEMORY="2048"
CORES="2"

# Download cloud image
wget "${IMAGE_URL}"

# Optional: Customize with virt-customize
apt install libguestfs-tools
virt-customize -a "${IMAGE_FILE}" \
  --install qemu-guest-agent,curl,vim \
  --run-command "systemctl enable qemu-guest-agent"

# Create and configure template VM
qm create "${TEMPLATE_VMID}" --name "${TEMPLATE_NAME}" --memory "${MEMORY}" --cores "${CORES}" --net0 "virtio,bridge=${BRIDGE}"
qm importdisk "${TEMPLATE_VMID}" "${IMAGE_FILE}" "${STORAGE}"
qm set "${TEMPLATE_VMID}" --scsihw virtio-scsi-pci --scsi0 "${STORAGE}:vm-${TEMPLATE_VMID}-disk-0"
qm set "${TEMPLATE_VMID}" --ide2 "${STORAGE}:cloudinit"
qm set "${TEMPLATE_VMID}" --serial0 socket --vga serial0
qm set "${TEMPLATE_VMID}" --boot order=scsi0
qm template "${TEMPLATE_VMID}"
```

---

## Key Decisions

### 1. Provider Choice: Telmate vs bpg/proxmox

| Aspect | Telmate/proxmox | bpg/proxmox |
|--------|-----------------|-------------|
| Maintenance | Actively maintained (2025+) | Actively maintained (latest: v0.92.0, Jan 2026) |
| Proxmox support | Basic VM/LXC/pool/cloud-init | Complete API coverage (VMs, clusters, hosts, ACLs, SDN, users) |
| Privilege separation | Some configuration deprecations | Handles privilege separation correctly |
| Proxmox 9.x support | Basic support | Full support, actively tested |
| Community feedback | Widely used, stable | "Perfectly maintained", fast bug fixes |
| **Recommendation** | Legacy projects, basic needs | **New projects, comprehensive management** |

**Decision**: Use `bpg/proxmox` for new infrastructure. Both providers are actively maintained, but bpg offers broader feature coverage and better support for newer Proxmox versions.

### 2. Clone Type: Full Clone vs Linked Clone

| Aspect | Full Clone | Linked Clone |
|--------|------------|--------------|
| Storage usage | High (independent disk) | Low (shares base) |
| Performance | Consistent | Depends on base disk |
| Independence | Fully independent | Tied to template |
| Migration | Easy | Template must exist on target |
| **Use case** | Production workloads | Development/testing |

**Decision**: Use **linked clones** for test clusters (saves storage), **full clones** for production.

### 3. Configuration Method: Terraform vs Cloud-init

| Configuration Type | Best Tool | Rationale |
|-------------------|-----------|-----------|
| VM resources (CPU, memory, disk) | Terraform | Infrastructure-level |
| Network assignment | Terraform | Ties to Proxmox bridges |
| User accounts, SSH keys | Cloud-init | OS-level, portable |
| Package installation | Cloud-init or virt-customize | Depends on when needed |
| Service configuration | Cloud-init `runcmd` | Post-boot customization |
| Container runtime setup | Cloud-init or Ansible | Complex, multi-step |

**Decision**: Use Terraform for infrastructure, cloud-init for OS configuration, consider Ansible for complex orchestration setup.

### 4. State Management

| Option | Pros | Cons |
|--------|------|------|
| Local state | Simple, no setup | Not collaborative, no locking |
| Remote state (S3/GCS) | Team collaboration, locking | Requires additional infra |
| Terraform Cloud | Managed, UI, history | Costs for large teams |

**Decision**: Start with local state for personal projects, migrate to remote state for team environments.

### 5. Environment Separation

| Strategy | Description | Best for |
|----------|-------------|----------|
| Directories | Separate dirs per environment | Simple, clear boundaries |
| Workspaces | Terraform workspaces | Similar configs, different vars |
| Branches | Git branches per environment | CI/CD integration |

**Decision**: Use **directory-based separation** for clarity.

---

## Tool Responsibilities

Understanding when to use each tool is critical for a clean architecture.

### The Three-Layer Stack

```
┌─────────────────────────────────────────────────────────────────────┐
│                        INFRASTRUCTURE LAYERS                        │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │ LAYER 0: Proxmox Host Setup (Optional - Ansible)             │  │
│  │ ─────────────────────────────────────────────────────────────│  │
│  │ • Install Proxmox on bare Debian (lae.proxmox role)          │  │
│  │ • Configure cluster membership                                │  │
│  │ • Set up Ceph storage                                        │  │
│  │ • Configure networking/SDN                                    │  │
│  └───────────────────────────────────────────────────────────────┘  │
│                              ▼                                      │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │ LAYER 1: VM Provisioning (Terraform)                         │  │
│  │ ─────────────────────────────────────────────────────────────│  │
│  │ • Create/destroy VMs from templates                          │  │
│  │ • Allocate resources (CPU, memory, disk)                     │  │
│  │ • Network assignment to bridges                              │  │
│  │ • IP address allocation via cloud-init                       │  │
│  └───────────────────────────────────────────────────────────────┘  │
│                              ▼                                      │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │ LAYER 2: OS Initialization (Cloud-init)                      │  │
│  │ ─────────────────────────────────────────────────────────────│  │
│  │ • User accounts and SSH keys                                 │  │
│  │ • Package installation                                       │  │
│  │ • Kernel modules and sysctl settings                         │  │
│  │ • First-boot scripts                                         │  │
│  └───────────────────────────────────────────────────────────────┘  │
│                              ▼                                      │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │ LAYER 3: Configuration Management (Ansible - Optional)       │  │
│  │ ─────────────────────────────────────────────────────────────│  │
│  │ • Complex software installation (k8s, Docker)                │  │
│  │ • Multi-node orchestration                                   │  │
│  │ • Day-2 operations (snapshots, updates)                      │  │
│  │ • Configuration drift remediation                            │  │
│  └───────────────────────────────────────────────────────────────┘  │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### When to Use Each Tool

| Task | Terraform | Cloud-init | Ansible |
|------|:---------:|:----------:|:-------:|
| **Create/destroy VMs** | ✅ | - | ⚠️ |
| **CPU/memory/disk allocation** | ✅ | - | - |
| **Network bridge assignment** | ✅ | - | - |
| **IP address configuration** | ✅ | ✅ | - |
| **User accounts & SSH keys** | - | ✅ | ✅ |
| **Base package installation** | - | ✅ | ✅ |
| **Kernel modules/sysctl** | - | ✅ | ✅ |
| **Complex software (k8s, etc.)** | - | ⚠️ | ✅ |
| **Multi-node coordination** | - | - | ✅ |
| **Day-2: VM snapshots** | - | - | ✅ |
| **Day-2: Rolling updates** | - | - | ✅ |
| **Day-2: Configuration drift detection** | ⚠️ | - | ✅ |
| **Day-2: Backup management** | - | - | ✅ |
| **Day-2: Security patching** | - | - | ✅ |
| **Day-2: Resource scaling** | ✅ | - | ⚠️ |
| **Day-2: Cluster maintenance** | - | - | ✅ |
| **Install Proxmox itself** | - | - | ✅ |

Legend: ✅ = Best choice | ⚠️ = Possible but not ideal | - = Not applicable

### Decision Matrix: When to Add Ansible

| Scenario | Terraform + Cloud-init | Add Ansible |
|----------|:----------------------:|:-----------:|
| Simple VMs with basic packages | ✅ | - |
| k3s single-node | ✅ | Optional |
| k3s/k8s multi-node cluster | ✅ | ✅ |
| Proxmox host installation | - | ✅ |
| Ceph storage setup | - | ✅ |
| Ongoing configuration management | - | ✅ |
| VM snapshots before updates | - | ✅ |

---

## Repository Structure

### Recommended Directory Layout

```
proxmox-infra/
├── README.md
├── .gitignore
├── .terraform-version          # Pin Terraform version
│
├── modules/                    # Reusable Terraform modules
│   ├── vm-base/               # Base VM module
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── k8s-node/              # Kubernetes node module
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── docker-host/           # Docker host module
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
│
├── environments/              # Environment-specific configurations
│   ├── dev/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── terraform.tfvars   # (gitignored)
│   │   └── outputs.tf
│   ├── staging/
│   │   └── ...
│   └── prod/
│       └── ...
│
├── cloud-init/                # Cloud-init configurations
│   ├── common/               # Shared configurations
│   │   ├── base-packages.yaml
│   │   └── ssh-hardening.yaml
│   ├── roles/                # Role-specific configurations
│   │   ├── k8s-control-plane.yaml
│   │   ├── k8s-worker.yaml
│   │   └── docker-host.yaml
│   └── instances/            # Instance-specific (generated)
│       └── .gitkeep
│
├── ansible/                   # Ansible configurations
│   ├── ansible.cfg           # Ansible settings
│   ├── requirements.yml      # Galaxy dependencies
│   ├── inventory/
│   │   ├── hosts.yml         # Static inventory
│   │   └── proxmox.yml       # Dynamic inventory (optional)
│   ├── group_vars/
│   │   ├── all.yml           # Variables for all hosts
│   │   ├── pve_hosts.yml     # Proxmox host variables
│   │   └── k8s_nodes.yml     # Kubernetes node variables
│   ├── host_vars/            # Per-host variables
│   │   └── .gitkeep
│   ├── roles/
│   │   └── proxmox_api/      # Custom roles
│   │       ├── tasks/main.yml
│   │       └── vars/main.yml
│   ├── playbooks/
│   │   ├── site.yml          # Main playbook
│   │   ├── proxmox-setup.yml # Proxmox host installation
│   │   ├── k8s-install.yml   # Kubernetes installation
│   │   └── snapshots.yml     # VM snapshot management
│   └── callbacks/
│       └── anstomlog.py      # Compact logging output
│
├── templates/                 # Template preparation scripts
│   ├── ubuntu-2404/
│   │   ├── prepare.sh
│   │   └── packages.txt
│   └── debian-12/
│       ├── prepare.sh
│       └── packages.txt
│
├── scripts/                   # Helper scripts
│   ├── deploy.sh
│   ├── destroy.sh
│   └── sync-snippets.sh      # Sync cloud-init to Proxmox
│
└── docs/
    └── setup.md
```

### Essential .gitignore

```gitignore
# Terraform
*.tfstate
*.tfstate.*
.terraform/
.terraform.lock.hcl
crash.log

# Secrets
*.tfvars
!*.tfvars.example
secrets/

# Generated
cloud-init/instances/*.yaml

# IDE
.idea/
.vscode/

# OS
.DS_Store
```

---

## Shared vs Individual Configuration

### Configuration Layering Strategy

```
┌─────────────────────────────────────────────────────────────┐
│                    TERRAFORM LAYER                          │
│  (Infrastructure: VM specs, networking, storage)            │
├─────────────────────────────────────────────────────────────┤
│                    SHARED CONFIGURATIONS                    │
├─────────────────────┬─────────────────┬─────────────────────┤
│   Base Packages     │  SSH Hardening  │  Common Users       │
│   (all VMs)         │  (all VMs)      │  (all VMs)          │
├─────────────────────┴─────────────────┴─────────────────────┤
│                    ROLE CONFIGURATIONS                      │
├─────────────────────┬─────────────────┬─────────────────────┤
│  Control Plane      │  Worker Node    │  Load Balancer      │
│  (k8s master pkgs)  │  (container rt) │  (haproxy/nginx)    │
├─────────────────────┴─────────────────┴─────────────────────┤
│                    INSTANCE CONFIGURATIONS                  │
├─────────────────────┬─────────────────┬─────────────────────┤
│  node1              │  node2          │  node3              │
│  (IP, hostname)     │  (IP, hostname) │  (IP, hostname)     │
└─────────────────────┴─────────────────┴─────────────────────┘
```

### What to Share (Reusable)

| Configuration | Location | Example |
|---------------|----------|---------|
| Base packages | `cloud-init/common/base-packages.yaml` | vim, curl, htop |
| SSH configuration | `cloud-init/common/ssh-hardening.yaml` | PermitRootLogin no |
| Admin users | `cloud-init/common/users.yaml` | admin user with sudo |
| Terraform modules | `modules/` | VM resource definitions |
| Provider config | `modules/` or root | Proxmox connection |

### What to Separate (Instance-Specific)

| Configuration | Location | Example |
|---------------|----------|---------|
| IP addresses | Terraform `locals` or `tfvars` | 10.0.50.21/24 |
| Hostnames | Terraform VM definition | k8s-control-01 |
| Node roles | Terraform module selection | control-plane vs worker |
| Secrets | `terraform.tfvars` (gitignored) | API tokens |
| Instance cloud-init | `cloud-init/instances/` | Generated per-VM |

### Cloud-init Composition Pattern

Cloud-init supports merging multiple config files. Use this pattern:

**cloud-init/common/base.yaml** (shared):
```yaml
#cloud-config
merge_how:
  - name: list
    settings: [append]
  - name: dict
    settings: [recurse_array]

package_update: true
package_upgrade: true

packages:
  - qemu-guest-agent
  - curl
  - vim
  - htop
  - net-tools

users:
  - name: admin
    groups: sudo
    shell: /bin/bash
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    ssh_authorized_keys:
      - ssh-rsa AAAA... your-key
```

**cloud-init/roles/k8s-node.yaml** (role-specific):
```yaml
#cloud-config
merge_how:
  - name: list
    settings: [append]
  - name: dict
    settings: [recurse_array]

packages:
  - apt-transport-https
  - ca-certificates
  - gnupg

write_files:
  - path: /etc/modules-load.d/k8s.conf
    content: |
      overlay
      br_netfilter

  - path: /etc/sysctl.d/k8s.conf
    content: |
      net.bridge.bridge-nf-call-iptables = 1
      net.bridge.bridge-nf-call-ip6tables = 1
      net.ipv4.ip_forward = 1

runcmd:
  - modprobe overlay
  - modprobe br_netfilter
  - sysctl --system
```

---

## Example: 3-Node Container Orchestration Cluster

Let's create a practical example for a 3-node cluster suitable for Kubernetes (k3s/k8s) or Docker Swarm.

### Cluster Architecture

```
┌────────────────────────────────────────────────────────────┐
│                    Test Cluster                            │
├────────────────────────────────────────────────────────────┤
│                                                            │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │   node-01    │  │   node-02    │  │   node-03    │     │
│  │  (control)   │  │  (worker)    │  │  (worker)    │     │
│  │              │  │              │  │              │     │
│  │ 10.0.50.11   │  │ 10.0.50.12   │  │ 10.0.50.13   │     │
│  │ 4 CPU / 8GB  │  │ 2 CPU / 4GB  │  │ 2 CPU / 4GB  │     │
│  └──────────────┘  └──────────────┘  └──────────────┘     │
│                                                            │
│           Bridge: vmbr0 | Subnet: 10.0.50.0/24            │
└────────────────────────────────────────────────────────────┘
```

### File Structure

```
environments/dev/
├── main.tf           # Main configuration
├── variables.tf      # Variable definitions
├── terraform.tfvars  # Actual values (gitignored)
├── terraform.tfvars.example  # Template for others
├── outputs.tf        # Output values
└── cloud-init/       # Environment-specific cloud-init
    ├── control-plane.yaml
    └── worker.yaml
```

### main.tf

```hcl
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.38.0"
    }
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_api_url
  insecure  = var.proxmox_tls_insecure
  api_token = var.proxmox_api_token
}

#─────────────────────────────────────────────────────────────
# Local Variables - Cluster Definition
#─────────────────────────────────────────────────────────────

locals {
  # Common settings for all nodes
  common = {
    template     = "ubuntu-2404-base"
    target_node  = var.proxmox_node
    storage      = "local-lvm"
    bridge       = "vmbr0"
    gateway      = "10.0.50.1"
    subnet       = "24"
    nameserver   = "10.0.50.1"
    searchdomain = "lab.local"
  }

  # Node definitions - this is where individual configs are specified
  cluster_nodes = {
    "k8s-control-01" = {
      vmid     = 501
      ip       = "10.0.50.11"
      cores    = 4
      memory   = 8192
      disk     = "40G"
      role     = "control-plane"
      tags     = ["kubernetes", "control-plane", "test"]
    }
    "k8s-worker-01" = {
      vmid     = 502
      ip       = "10.0.50.12"
      cores    = 2
      memory   = 4096
      disk     = "30G"
      role     = "worker"
      tags     = ["kubernetes", "worker", "test"]
    }
    "k8s-worker-02" = {
      vmid     = 503
      ip       = "10.0.50.13"
      cores    = 2
      memory   = 4096
      disk     = "30G"
      role     = "worker"
      tags     = ["kubernetes", "worker", "test"]
    }
  }
}

#─────────────────────────────────────────────────────────────
# VM Resources
#─────────────────────────────────────────────────────────────

resource "proxmox_virtual_environment_vm" "cluster_node" {
  for_each = local.cluster_nodes

  name        = each.key
  description = "K8s ${each.value.role} node - managed by Terraform"
  tags        = each.value.tags
  node_name   = local.common.target_node
  vm_id       = each.value.vmid

  # Clone from template
  clone {
    vm_id = var.template_vmid
    full  = var.full_clone
  }

  # Hardware configuration
  cpu {
    cores = each.value.cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = each.value.memory
  }

  # Boot disk - resize from template
  disk {
    datastore_id = local.common.storage
    interface    = "scsi0"
    size         = tonumber(replace(each.value.disk, "G", ""))
    file_format  = "raw"
  }

  # Network
  network_device {
    bridge = local.common.bridge
    model  = "virtio"
  }

  # Cloud-init configuration
  initialization {
    ip_config {
      ipv4 {
        address = "${each.value.ip}/${local.common.subnet}"
        gateway = local.common.gateway
      }
    }

    dns {
      servers = [local.common.nameserver]
      domain  = local.common.searchdomain
    }

    user_account {
      username = var.vm_user
      keys     = [trimspace(file(var.ssh_public_key_path))]
    }

    # Use role-specific cloud-init
    user_data_file_id = proxmox_virtual_environment_file.cloud_init[each.value.role].id
  }

  # Ensure QEMU guest agent is enabled
  agent {
    enabled = true
  }

  # Start on boot
  on_boot = true

  lifecycle {
    ignore_changes = [
      # Ignore boot disk size changes after initial creation
      disk[0].size,
    ]
  }
}

#─────────────────────────────────────────────────────────────
# Cloud-init Files Upload
#─────────────────────────────────────────────────────────────

resource "proxmox_virtual_environment_file" "cloud_init" {
  for_each = toset(["control-plane", "worker"])

  content_type = "snippets"
  datastore_id = "local"
  node_name    = local.common.target_node

  source_raw {
    data      = file("${path.module}/cloud-init/${each.key}.yaml")
    file_name = "ci-${each.key}.yaml"
  }
}
```

### variables.tf

```hcl
#─────────────────────────────────────────────────────────────
# Provider Configuration
#─────────────────────────────────────────────────────────────

variable "proxmox_api_url" {
  description = "Proxmox API URL (e.g., https://10.0.1.241:8006)"
  type        = string
}

variable "proxmox_api_token" {
  description = "Proxmox API Token in format 'user@realm!tokenid=secret'"
  type        = string
  sensitive   = true
}

variable "proxmox_tls_insecure" {
  description = "Skip TLS verification (set false in production)"
  type        = bool
  default     = true
}

variable "proxmox_node" {
  description = "Target Proxmox node name"
  type        = string
  default     = "pve"
}

#─────────────────────────────────────────────────────────────
# Template Configuration
#─────────────────────────────────────────────────────────────

variable "template_vmid" {
  description = "VM ID of the template to clone from"
  type        = number
  default     = 9000
}

variable "full_clone" {
  description = "Create full clone (true) or linked clone (false)"
  type        = bool
  default     = false  # Linked clone for dev/test
}

#─────────────────────────────────────────────────────────────
# VM Configuration
#─────────────────────────────────────────────────────────────

variable "vm_user" {
  description = "Default user for VMs"
  type        = string
  default     = "admin"
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key for VM authentication"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}
```

### terraform.tfvars.example

```hcl
# Copy this file to terraform.tfvars and fill in your values
# terraform.tfvars will be ignored by the .gitignore pattern shown above and should never be committed

proxmox_api_url      = "https://YOUR_PROXMOX_IP:8006"
proxmox_api_token    = "terraform-prov@pve!automation=YOUR_TOKEN_SECRET"
proxmox_tls_insecure = true
proxmox_node         = "pve"

template_vmid        = 9000
full_clone           = false

vm_user              = "admin"
ssh_public_key_path  = "~/.ssh/id_rsa.pub"
```

### outputs.tf

```hcl
output "cluster_nodes" {
  description = "Cluster node information"
  value = {
    for name, vm in proxmox_virtual_environment_vm.cluster_node : name => {
      vmid = vm.vm_id
      ip   = local.cluster_nodes[name].ip
      role = local.cluster_nodes[name].role
    }
  }
}

output "control_plane_ip" {
  description = "Control plane node IP address"
  value = [
    for name, node in local.cluster_nodes :
    node.ip if node.role == "control-plane"
  ][0]
}

output "worker_ips" {
  description = "Worker node IP addresses"
  value = [
    for name, node in local.cluster_nodes :
    node.ip if node.role == "worker"
  ]
}

output "ssh_command" {
  description = "SSH command to connect to control plane"
  value       = "ssh ${var.vm_user}@${local.cluster_nodes["k8s-control-01"].ip}"
}
```

### cloud-init/control-plane.yaml

```yaml
#cloud-config
package_update: true
package_upgrade: true

packages:
  - qemu-guest-agent
  - curl
  - vim
  - htop
  - net-tools
  - apt-transport-https
  - ca-certificates
  - gnupg

write_files:
  # Kernel modules for Kubernetes
  - path: /etc/modules-load.d/k8s.conf
    content: |
      overlay
      br_netfilter

  # Sysctl settings for Kubernetes networking
  - path: /etc/sysctl.d/k8s.conf
    content: |
      net.bridge.bridge-nf-call-iptables = 1
      net.bridge.bridge-nf-call-ip6tables = 1
      net.ipv4.ip_forward = 1

  # Marker file to identify control plane
  - path: /etc/k8s-role
    content: |
      control-plane

runcmd:
  # Enable QEMU guest agent
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent

  # Load kernel modules
  - modprobe overlay
  - modprobe br_netfilter
  - sysctl --system

  # Signal that cloud-init completed
  - touch /var/lib/cloud/instance/cloud-init-complete
```

### cloud-init/worker.yaml

```yaml
#cloud-config
package_update: true
package_upgrade: true

packages:
  - qemu-guest-agent
  - curl
  - vim
  - htop
  - net-tools
  - apt-transport-https
  - ca-certificates
  - gnupg

write_files:
  # Kernel modules for Kubernetes
  - path: /etc/modules-load.d/k8s.conf
    content: |
      overlay
      br_netfilter

  # Sysctl settings for Kubernetes networking
  - path: /etc/sysctl.d/k8s.conf
    content: |
      net.bridge.bridge-nf-call-iptables = 1
      net.bridge.bridge-nf-call-ip6tables = 1
      net.ipv4.ip_forward = 1

  # Marker file to identify worker
  - path: /etc/k8s-role
    content: |
      worker

runcmd:
  # Enable QEMU guest agent
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent

  # Load kernel modules
  - modprobe overlay
  - modprobe br_netfilter
  - sysctl --system

  # Signal that cloud-init completed
  - touch /var/lib/cloud/instance/cloud-init-complete
```

---

## Workflow

### Initial Setup

```bash
# 1. Navigate to environment
cd environments/dev

# 2. Create your tfvars from example
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

# 3. Initialize Terraform
terraform init

# 4. Preview changes
terraform plan

# 5. Apply
terraform apply
```

### Day-to-Day Operations

```bash
# Check cluster status
terraform output

# SSH to control plane
eval $(terraform output -raw ssh_command)

# Add a new worker (edit locals.cluster_nodes in main.tf, then:)
terraform plan
terraform apply

# Destroy entire cluster
terraform destroy
```

### Scaling Pattern

To add more nodes, simply extend the `cluster_nodes` local:

```hcl
locals {
  cluster_nodes = {
    # ... existing nodes ...

    "k8s-worker-03" = {
      vmid     = 504
      ip       = "10.0.50.14"
      cores    = 2
      memory   = 4096
      disk     = "30G"
      role     = "worker"
      tags     = ["kubernetes", "worker", "test"]
    }
  }
}
```

---

## Best Practices Summary

| Area | Recommendation |
|------|----------------|
| **Secrets** | Never commit `.tfvars`, use `.tfvars.example` as template |
| **State** | Start local, migrate to remote for teams |
| **Templates** | Prepare with virt-customize, minimize cloud-init work |
| **Cloud-init** | Separate into common/role/instance layers |
| **Cloning** | Linked for dev/test, full for production |
| **Modules** | Extract when patterns repeat 3+ times |
| **Naming** | Use consistent naming: `{project}-{role}-{number}` |
| **Tags** | Tag VMs for easy filtering in Proxmox UI |
| **Documentation** | Keep `README.md` updated with setup instructions |

---

## Next Steps After VM Provisioning

Once your VMs are running, you have several options for container orchestration:

| Option | Complexity | Best For |
|--------|------------|----------|
| **k3s** | Low | Quick setup, edge, dev/test |
| **kubeadm** | Medium | Learning, production-like |
| **Docker Swarm** | Low | Simple orchestration needs |
| **Ansible + k8s** | Medium-High | Full automation, production |

For a test cluster, I recommend **k3s** as it can be installed with a single command and supports multi-node clusters easily.

---

## Ansible Integration

Ansible complements Terraform and cloud-init for scenarios requiring multi-node coordination, complex software installation, or day-2 operations.

### Installing Ansible Dependencies

```bash
# On Ubuntu (recommended for Ansible control node)
sudo add-apt-repository ppa:ansible/ansible
sudo apt update
sudo apt install ansible python3-jmespath

# Install required collections and roles
cd ansible/
ansible-galaxy install -r requirements.yml
```

### ansible/requirements.yml

```yaml
---
roles:
  - name: lae.proxmox
    version: ">=1.0.0"

collections:
  - name: community.proxmox
    version: ">=1.0.0"
```

### ansible/ansible.cfg

```ini
[defaults]
inventory = ./inventory/hosts.yml
roles_path = ./roles:~/.ansible/roles
callback_plugins = ./callbacks
stdout_callback = anstomlog

# Performance
forks = 10
pipelining = True

# SSH settings
host_key_checking = False
retry_files_enabled = False
interpreter_python = auto_silent

[privilege_escalation]
become = True
become_method = sudo
become_user = root
```

### ansible/inventory/hosts.yml

```yaml
---
all:
  children:
    # Proxmox hypervisor hosts (for lae.proxmox role)
    pve_hosts:
      hosts:
        proxmox01.lab.local:
          ansible_host: 10.0.50.1

    # Kubernetes cluster nodes (provisioned by Terraform)
    k8s_cluster:
      children:
        k8s_control_plane:
          hosts:
            k8s-control-01:
              ansible_host: 10.0.50.11
        k8s_workers:
          hosts:
            k8s-worker-01:
              ansible_host: 10.0.50.12
            k8s-worker-02:
              ansible_host: 10.0.50.13

  vars:
    ansible_user: admin
    ansible_ssh_private_key_file: ~/.ssh/id_rsa
```

### ansible/group_vars/all.yml

```yaml
---
# Proxmox API connection (shared across playbooks)
proxmox_host: "10.0.50.1"
proxmox_user: "terraform-prov@pve"
proxmox_token_id: "automation"
# proxmox_token_secret: defined in vault or env var
```

### ansible/group_vars/pve_hosts.yml

```yaml
---
# Settings for lae.proxmox role
pve_group: pve_hosts
pve_reboot_on_kernel_update: true
pve_no_subscription_repo: true
pve_remove_old_kernels: true

# Storage configuration
pve_storages:
  - name: local-lvm
    type: lvmthin
    content: ["images", "rootdir"]
    thinpool: data
    vgname: pve
```

### Example Playbooks

#### ansible/playbooks/proxmox-setup.yml

Install Proxmox on bare Debian hosts:

```yaml
---
- name: Install Proxmox VE on Debian hosts
  hosts: pve_hosts
  become: true

  roles:
    - lae.proxmox

  vars:
    pve_reboot_on_kernel_update: true
```

#### ansible/playbooks/k8s-install.yml

Install k3s on Terraform-provisioned VMs:

```yaml
---
- name: Install k3s control plane
  hosts: k8s_control_plane
  become: true
  vars:
    k3s_token: "{{ lookup('password', 'k3s_token length=32 chars=ascii_letters,digits') }}"

  tasks:
    # Security Note: This installation method downloads and executes a script from the internet.
    # For production deployments, consider:
    # 1. Pinning a specific k3s version: Add INSTALL_K3S_VERSION=v1.28.5+k3s1 before the curl command
    # 2. Verifying checksums: Download the script first and verify its checksum before execution
    # 3. Using a local mirror: Host the installation script on your internal infrastructure
    - name: Install k3s server
      ansible.builtin.shell: |
        curl -sfL https://get.k3s.io | sh -s - server \
          --token {{ k3s_token }} \
          --tls-san {{ ansible_host }}
      args:
        creates: /usr/local/bin/k3s

    - name: Save k3s token for workers
      ansible.builtin.set_fact:
        k3s_server_token: "{{ k3s_token }}"
        k3s_server_url: "https://{{ ansible_host }}:6443"
      delegate_to: localhost
      delegate_facts: true

- name: Install k3s workers
  hosts: k8s_workers
  become: true

  tasks:
    - name: Install k3s agent
      ansible.builtin.shell: |
        curl -sfL https://get.k3s.io | sh -s - agent \
          --server {{ hostvars['localhost']['k3s_server_url'] }} \
          --token {{ hostvars['localhost']['k3s_server_token'] }}
      args:
        creates: /usr/local/bin/k3s-agent
```

#### ansible/playbooks/snapshots.yml

Manage VM snapshots via Proxmox API:

```yaml
---
- name: Create VM snapshots before maintenance
  hosts: localhost
  gather_facts: false

  vars:
    snapshot_name: "pre-update-{{ ansible_date_time.date }}"
    target_vms:
      - 501  # k8s-control-01
      - 502  # k8s-worker-01
      - 503  # k8s-worker-02

  tasks:
    - name: Create snapshot for each VM
      community.proxmox.proxmox_snap:
        api_host: "{{ proxmox_host }}"
        api_user: "{{ proxmox_user }}"
        api_token_id: "{{ proxmox_token_id }}"
        api_token_secret: "{{ proxmox_token_secret }}"
        vmid: "{{ item }}"
        snapname: "{{ snapshot_name }}"
        state: present
        description: "Automated pre-update snapshot"
      loop: "{{ target_vms }}"
```

#### ansible/playbooks/vm-power.yml

Control VM power state:

```yaml
---
- name: Control VM power state
  hosts: localhost
  gather_facts: false

  vars:
    vm_state: started  # started, stopped, restarted
    target_vmids: [501, 502, 503]

  tasks:
    - name: Set VM power state
      community.proxmox.proxmox_kvm:
        api_host: "{{ proxmox_host }}"
        api_user: "{{ proxmox_user }}"
        api_token_id: "{{ proxmox_token_id }}"
        api_token_secret: "{{ proxmox_token_secret }}"
        vmid: "{{ item }}"
        state: "{{ vm_state }}"
      loop: "{{ target_vmids }}"
```

### Combined Workflow: Terraform + Ansible

The recommended workflow uses Terraform for provisioning and Ansible for configuration:

```bash
# 1. Provision VMs with Terraform
cd environments/dev
terraform init
terraform apply

# 2. Change to Ansible directory
cd ../../ansible

# 3. Wait for VMs to be ready (cloud-init complete on all hosts)
ansible all -m ansible.builtin.wait_for -a "path=/var/lib/cloud/instance/boot-finished state=present timeout=600"

# 4. Run Ansible for complex configuration
ansible-playbook playbooks/k8s-install.yml

# 5. Verify cluster
ansible k8s_control_plane -m shell -a "kubectl get nodes"
```

### Terraform-Ansible Integration: Dynamic Inventory

For dynamic inventory generation from Terraform state:

#### scripts/generate-inventory.sh

```bash
#!/bin/bash
# Generate Ansible inventory from Terraform output

# Variables
TERRAFORM_ENV="environments/dev"
ANSIBLE_INVENTORY_DIR="ansible/inventory"
OUTPUT_FILE="terraform-hosts.yml"

# Change to Terraform environment directory
cd "${TERRAFORM_ENV}"

# Generate inventory from Terraform output
terraform output -json cluster_nodes | jq -r '
  to_entries |
  group_by(.value.role) |
  map({
    key: (.[0].value.role | gsub("-"; "_")),
    value: {hosts: map({key: .key, value: {ansible_host: .value.ip}}) | from_entries}
  }) |
  {all: {children: from_entries}}
' > "../../${ANSIBLE_INVENTORY_DIR}/${OUTPUT_FILE}"

echo "Inventory generated at ${ANSIBLE_INVENTORY_DIR}/${OUTPUT_FILE}"
```

### When to Use Each Approach

| Scenario | Approach |
|----------|----------|
| **New cluster from scratch** | Terraform → Cloud-init → Ansible |
| **Add node to existing cluster** | Terraform → Ansible (join cluster) |
| **Update all nodes** | Ansible only (rolling update playbook) |
| **Pre-maintenance snapshots** | Ansible only (snapshot playbook) |
| **Destroy and recreate** | Terraform destroy → Terraform apply |
| **Install Proxmox on bare metal** | Ansible only (lae.proxmox) |

### Secrets Management

For Ansible secrets (API tokens, passwords):

```bash
# Create encrypted vault file
ansible-vault create ansible/group_vars/vault.yml

# Add to vault.yml:
# proxmox_token_secret: "your-api-token-secret"

# Run playbook with vault
ansible-playbook playbooks/snapshots.yml --ask-vault-pass

# Or use environment variable
export ANSIBLE_VAULT_PASSWORD_FILE=~/.vault_pass
```

### Complete Infrastructure Lifecycle

```
┌─────────────────────────────────────────────────────────────────┐
│                    INFRASTRUCTURE LIFECYCLE                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐         │
│  │   CREATE    │    │  CONFIGURE  │    │   OPERATE   │         │
│  │  (Day 0)    │───▶│  (Day 1)    │───▶│  (Day 2+)   │         │
│  └─────────────┘    └─────────────┘    └─────────────┘         │
│        │                  │                  │                  │
│        ▼                  ▼                  ▼                  │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐         │
│  │  Terraform  │    │ Cloud-init  │    │   Ansible   │         │
│  │  + cloud-   │    │ + Ansible   │    │             │         │
│  │    init     │    │             │    │             │         │
│  └─────────────┘    └─────────────┘    └─────────────┘         │
│        │                  │                  │                  │
│        ▼                  ▼                  ▼                  │
│  • Create VMs       • Install k8s      • Snapshots            │
│  • Assign IPs       • Join cluster     • Updates              │
│  • Base packages    • Deploy apps      • Scaling              │
│  • SSH keys         • Certificates     • Monitoring           │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```
