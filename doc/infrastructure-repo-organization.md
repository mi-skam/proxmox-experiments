# Organizing a Proxmox Infrastructure Repository

This guide explains how to structure an infrastructure repository for creating VMs on a Proxmox cluster using Terraform and cloud-init, with a practical example of a 3-node container orchestration test cluster.

## Table of Contents

1. [Requirements](#requirements)
2. [Key Decisions](#key-decisions)
3. [Repository Structure](#repository-structure)
4. [Shared vs Individual Configuration](#shared-vs-individual-configuration)
5. [Example: 3-Node Container Orchestration Cluster](#example-3-node-container-orchestration-cluster)

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
# Create user
pveum user add terraform-prov@pve --password "secure-password"

# Create role with required privileges
pveum role add TerraformProv -privs "Datastore.AllocateSpace Datastore.AllocateTemplate Datastore.Audit Pool.Allocate Pool.Audit Sys.Audit Sys.Console Sys.Modify VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.CPU VM.Config.Cloudinit VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Migrate VM.PowerMgmt SDN.Use"

# Create group and assign role
pveum group add terraform
pveum aclmod / -group terraform -role TerraformProv
pveum user modify terraform-prov@pve -groups terraform

# Create API token (save the output!)
pveum user token add terraform-prov@pve automation
```

### Base Template Preparation

Before Terraform can provision VMs, you need a cloud-init enabled template:

```bash
# Download cloud image
wget https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img

# Optional: Customize with virt-customize
apt install libguestfs-tools
virt-customize -a noble-server-cloudimg-amd64.img \
  --install qemu-guest-agent,curl,vim \
  --run-command "systemctl enable qemu-guest-agent"

# Create and configure template VM
qm create 9000 --name ubuntu-2404-base --memory 2048 --cores 2 --net0 virtio,bridge=vmbr0
qm importdisk 9000 noble-server-cloudimg-amd64.img local-lvm
qm set 9000 --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-9000-disk-0
qm set 9000 --ide2 local-lvm:cloudinit
qm set 9000 --serial0 socket --vga serial0
qm set 9000 --boot order=scsi0
qm template 9000
```

---

## Key Decisions

### 1. Provider Choice: Telmate vs bpg/proxmox

| Aspect | Telmate/proxmox | bpg/proxmox |
|--------|-----------------|-------------|
| Maturity | Older, widely used | Newer, actively maintained |
| Privilege separation | Issues with newer Proxmox | Handles correctly |
| Documentation | More examples available | Growing community |
| **Recommendation** | Legacy projects | **New projects** |

**Decision**: Use `bpg/proxmox` for new infrastructure.

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
      # Ignore disk changes after initial creation
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
# terraform.tfvars is gitignored and should never be committed

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
