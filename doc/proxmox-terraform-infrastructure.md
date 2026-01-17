# Proxmox and Terraform: Controlled Infrastructure

> **Source**: iX Magazine 1/2026, Article by Thomas Joos

With Terraform, you can define even complex Proxmox infrastructures in a traceable manner and automate many processes. The Proxmox API, templates, and Terraform provider must work together.

## Overview

Proxmox Virtual Environment (VE) provides a system with clearly defined interfaces whose management logic is suitable for fully automatable infrastructure. The open-source tool Terraform controls the infrastructure setup in the cloud and on-premises in a repeatable and automated way (Infrastructure as Code, IaC).

The workflow appears simple at first glance: a provider, a few configuration files (HCL - HashiCorp Configuration Language), a plan, an apply. However, upon closer examination, it develops its own depth. The interplay of Proxmox API, templates, internal provider structure, permission requirements, and state model behavior enables reproducible, automated deployments without repetitions or manual rework.

Terraform also works with Cloud-init to further advance the automation of a Proxmox environment.

## Key Points

- The Infrastructure-as-Code tool Terraform makes Proxmox infrastructures reproducible, versionable, and traceable through configuration files
- Via the API, all system objects for provisioning, migrating, and cloning virtual machines can be represented
- From a single Terraform definition, many VMs can be created
- The permission model and the interplay of Proxmox and Terraform definitions can contain pitfalls in daily operations

## Provider, API and Authorization Model

Terraform interacts with Proxmox via its REST API. The entry point is always `api2/json`, regardless of whether individual nodes or the entire cluster are addressed. For the provider, this API is the only communication channel. Everything Terraform executes runs over the same API routes that the web interface uses. The provider configuration forms this interface.

Authentication is done via a dedicated service account. For a secure process, administrators should use a completely isolated account, as they can control role assignments, token validity, and permissions. The creation always follows the same pattern.

## Setting Up Authentication

### Step 1: Create User and Token

In the following example, the Proxmox host has IP address `10.0.1.241`. Integration of Terraform can be done in the shell or via an existing SSH session.

First, create a service account for Terraform so that API accesses run separately from interactive logins:

```bash
pveum user add terraform-prov@pve --password "xyz"
```

This creates the new user in the Proxmox user database.

### Step 2: Create Role with Privileges

Next, the role profile bundles all rights that the Terraform provider needs:

```bash
pveum role add TerraformProv -privs "Datastore.AllocateSpace Datastore.AllocateTemplate Datastore.Audit Pool.Allocate Pool.Audit Sys.Audit Sys.Console Sys.Modify VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.CPU VM.Config.Cloudinit VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Migrate VM.PowerMgmt SDN.Use"
```

### Step 3: Create Group and Assign Role

```bash
pveum group add terraform
```

This creates a group. Then link this group with the role at the cluster base level:

```bash
pveum aclmod / -group terraform -role TerraformProv
```

### Step 4: Add User to Group

```bash
pveum user modify terraform-prov@pve -groups terraform
```

### Step 5: Create API Token

In the next step, the account receives an API token:

```bash
pveum user token add terraform-prov@pve automation
```

The output of this command shows a Token-ID and a Secret. Both values should be noted immediately, as they will later be used as variables in Terraform.

## Terraform Installation

On Proxmox, update the package sources with `apt update` and install the required tools with `apt install curl unzip`. Terraform is loaded directly from the HashiCorp servers:

```bash
curl -O https://releases.hashicorp.com/terraform/1.13.5/terraform_1.13.5_linux_amd64.zip
```

The current version can be found on the release website. After download, the archive is unpacked and the binary is moved to the system path `/usr/local/bin/terraform` so that Terraform is available as a regular command on the entire system.

Verify installation:
```bash
terraform version
```

Create a project directory for later automation:
```bash
mkdir tf-proxmox
cd tf-proxmox
```

## Terraform Provider Configuration

### provider.tf (Using Telmate Provider)

Create the file `provider.tf` in the Terraform directory. It controls the connection between Terraform and the Proxmox host and contains the complete provider configuration including API URL and both token values.

```hcl
terraform {
  required_providers {
    proxmox = {
      source = "Telmate/proxmox"
    }
  }
}

provider "proxmox" {
  pm_api_url          = "https://10.0.1.241:8006/api2/json"
  pm_api_token_id     = "terraform-prov@pve!automation"
  pm_api_token_secret = "79f1a87e-3d4f-4feb-9350-e7758fabd173"
  pm_tls_insecure     = true
}
```

### Alternative: Using Variables File (terraform.tfvars)

To know which token values should be used, additionally create the file `terraform.tfvars` and enter the Token-ID and Token-Secret there:

```hcl
proxmox_token_id     = "terraform-prov@pve!automation"
proxmox_token_secret = "79f1a87e-3d4f-4feb-9350-e7758fabd173"
```

When token values are in the `provider.tf` file, Terraform doesn't need a `terraform.tfvars` file.

### Alternative Provider: bpg/proxmox

The most practical solution is to switch to the actively maintained alternative provider (bpg/proxmox). It uses the same API path but processes privilege separation correctly and allows functioning automation on Proxmox systems without adjustment. Users simply adapt the provider block and use the familiar Terraform workflows.

```hcl
terraform {
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
    }
  }
}

provider "proxmox" {
  endpoint  = "https://10.0.1.241:8006/api2/json"
  insecure  = true
  api_token = "terraform-prov@pve!automation=db14a893-9213-4fbc-8994-62451b3aea74"
}
```

### Initialize Terraform

Once the files are saved, the Terraform environment is initialized:

```bash
terraform init
```

Terraform connects with the host, loads the current version of the Telmate-provided Proxmox provider (for VM provisioning) from the Terraform Registry, and sets up the working environment. At this point, it accepts additional configuration files and can later provision VMs in the cluster. All functions are then available to create VM definitions as HCL files and provide them via additional commands.

## Templates, Cloud-init and Prepared Images

Terraform requires a template. Provisioning begins by importing a suitable Cloud-init image into Proxmox, providing it with the Cloud-init drive, and then converting it to a template. The difference is that Terraform automatically sets the Cloud-init parameters and transfers them with the apply process.

A template contains the operating system, Cloud-init packages, and basic configuration like drive types, serial consoles, and boot order. Terraform combines this template with VM-specific parameters. This keeps reusable base images separate from dynamic deployments.

Integration with Virt-Customize also plays a role. This tool modifies Cloud images directly on the host. Packages, services, files on startup commands can be integrated into the template without the VM itself needing to start. Templates become more homogeneous, and Terraform needs to process fewer variables.

#### Using Virt-Customize to Modify Cloud Images

Virt-Customize, part of the libguestfs-tools package, allows you to customize cloud images before converting them to templates. First, ensure the package is installed on your Proxmox host:

```bash
apt install libguestfs-tools
```

Here are practical examples of common customizations:

##### Listing 4a: Install Packages and Configure Services

```bash
# Install packages into the cloud image
virt-customize -a noble-server-cloudimg-amd64.img \
  --install qemu-guest-agent,vim,htop,curl

# Enable services to start on boot
virt-customize -a noble-server-cloudimg-amd64.img \
  --run-command "systemctl enable qemu-guest-agent"
```

##### Listing 4b: Add Files and Configure System Settings

```bash
# Create a custom configuration file
virt-customize -a noble-server-cloudimg-amd64.img \
  --write /etc/custom-config.conf:"key=value\nother_key=other_value"

# Copy a file from the host into the image
virt-customize -a noble-server-cloudimg-amd64.img \
  --copy-in /path/to/local/file:/etc/

# Run custom commands
virt-customize -a noble-server-cloudimg-amd64.img \
  --run-command "echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf"
```

##### Listing 4c: Comprehensive Example with Multiple Customizations

```bash
# Combine multiple operations in a single command
virt-customize -a noble-server-cloudimg-amd64.img \
  --install qemu-guest-agent,ansible,git \
  --run-command "systemctl enable qemu-guest-agent" \
  --mkdir /opt/scripts \
  --write /opt/scripts/startup.sh:"#!/bin/bash\necho 'System initialized'" \
  --chmod 0755:/opt/scripts/startup.sh \
  --timezone Europe/Berlin
```

After customizing the image with Virt-Customize, proceed with importing it to Proxmox and converting to a template. This approach reduces the configuration burden on Cloud-init and Terraform, as the base image already contains necessary packages and configurations.

### Preparing a Cloud-Init Image

Cloud images can be downloaded in the shell. Ubuntu 24.04 LTS for example with wget from `https://cloud-images.ubuntu.com/noble/current/` - the image is `noble-server-cloudimg-amd64.img`.

Once downloaded to the current project directory, prepare it on the Proxmox host in several steps for later cloning by Terraform.

#### Listing 5: Prepare VM for Terraform and Cloud-init

```bash
# Create VM with basic settings
qm create 9500 --name ubuntu-2404-ci --memory 4096 --cores 4 --net0 virtio,bridge=vmbr0

# Import disk to storage
qm importdisk 9500 noble-server-cloudimg-amd64.img local-lvm

# Configure SCSI controller and attach disk
qm set 9500 --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-9500-disk-0

# Add Cloud-init drive
qm set 9500 --ide2 local-lvm:cloudinit

# Enable serial console (required for Ubuntu Cloud images)
qm set 9500 --serial0 socket --vga serial0

# Set boot order to SCSI disk
qm set 9500 --boot order=scsi0

# Convert to template
qm template 9500
```

The template is now named `ubuntu-2404-ci` and can be referenced in Terraform via `clone = "ubuntu-2404-ci"` or via the ID `clone = "9500"`.

## VM Configuration for Terraform

The VM configuration for using Terraform is in the file `vm.tf`. A complete, functional configuration can look like this:

### Listing 6: Complete VM Configuration

```hcl
resource "proxmox_vm_qemu" "web01" {
  name        = "web01"
  target_node = "proxmox"
  clone       = "ubuntu-2404-ci"
  full_clone  = true
  cores       = 4
  memory      = 4096
  scsihw      = "virtio-scsi-pci"

  disk {
    type    = "scsi"
    storage = "local-lvm"
    size    = "20G"
  }

  network {
    model  = "virtio"
    bridge = "vmbr0"
  }

  ciuser    = "admin"
  sshkeys   = file("~/.ssh/id_rsa.pub")
  ipconfig0 = "ip=dhcp"
}
```

The configuration must match the cluster conditions. Enter the environment data here: `clone` points to the template and `target_node` names the Proxmox node where the VM will be deployed. The storage block must contain the correct storage name. The bridge name depends on the host's network configuration. If the data is incorrect, the process fails.

### User Data Initialization (Alternative to SSH Keys)

Instead of defining an SSH key, you can specify username and password in the `vm.tf` file:

```hcl
initialization {
  user_account {
    username = "ubuntu"
    password = "xyz"
  }
}
```

Instead of the line `sshkeys = file("~/.ssh/id_rsa.pub")`.

## Creating VMs with Terraform

After the `vm.tf` file is saved in the project folder, the actual Terraform workflow follows.

### Step 1: Initialize (if not already done)

```bash
terraform init
```

Or upgrade providers:
```bash
terraform init -upgrade
```

### Step 2: Plan

```bash
terraform plan
```

The `terraform plan` command checks all files in the directory and shows which actions will be executed. Errors like wrong template names, non-existing storage, or typos in hostnames are immediately recognized.

### Step 3: Apply

Terraform shows the proposed changes, which you confirm with `yes`. Proxmox then begins cloning the template, creates the new volume, assigns the parameters from `vm.tf`, and creates the VM with the defined resources. In the task log of the Proxmox host, all steps can be followed in real-time. Once Terraform reports completion, the new VM is in the cluster.

```bash
terraform apply
```

In the Proxmox interface, you can then open the VM and check via the console whether Cloud-init has completed and the DHCP server has assigned an address.

### Step 4: Verify Cloud-init Status

In the guest system, verify Cloud-init directly:

```bash
sudo cloud-init status
```

Shows whether all modules completed successfully.

```bash
sudo cloud-init logs
```

Provides additional details if the VM behaves unexpectedly.

### Cleanup

If the VM was created for testing purposes or is no longer needed, it can be completely removed via:

```bash
terraform destroy
```

This removes the VM including storage volumes. The project folder remains unchanged and can be reused for new deployments at any time.

## Creating Multiple VM Instances

Multiple VMs can be created at once using the `locals` and `for_each` constructs. The configuration extends through a mechanism that creates different systems from a single definition.

### Listing 8: Four VM Instances

```hcl
locals {
  server_group = {
    "frontend01" = { ip = "10.0.50.21", gw = "10.0.50.1" }
    "frontend02" = { ip = "10.0.50.22", gw = "10.0.50.1" }
    "backend01"  = { ip = "10.0.50.31", gw = "10.0.50.1" }
    "backend02"  = { ip = "10.0.50.32", gw = "10.0.50.1" }
  }
}

resource "proxmox_vm_qemu" "group" {
  for_each    = local.server_group
  name        = each.key
  target_node = "proxmox"
  clone       = "ubuntu-ci-template"
  full_clone  = true
  cores       = 2
  memory      = 4096
  scsihw      = "virtio-scsi-pci"
  ipconfig0   = "ip=${each.value.ip}/24,gw=${each.value.gw}"
  ciuser      = "admin"
  sshkeys     = file("~/.ssh/id_rsa.pub")
}
```

Terraform creates four instances in this example, each with its own IP address.

## Resource Model and State Mechanics

Terraform uses `proxmox_vm_qemu` and `proxmox_lxc` as central resource types. Both represent the Proxmox system structure extensively. The definition of a VM contains name, target_node, clone, full_clone, cores, sockets, scsihw, memory, and all network and storage parameters. The provider also automatically creates the Cloud-init drive once a Cloud-init option (ci) is set.

The state contains the VM-ID assignment, reference to storage volumes, and metadata for network, operating system type, and Cloud-init. Any deviation between configuration and current state appears in `terraform plan` as a planned intervention.

The `terraform plan` command ensures that Terraform correctly recognizes the VM in the next run. This plan should show no more changes. If Terraform reports "no changes", the provider is working with the internal status of the VM.

## Common Problems and Solutions

### Permission Issues

Problems during deployment often result from non-existing template names, missing permissions, or storage errors. A wrong bridge name leads to unreachable instances.

If a permission problem exists that prevents Terraform from cloning the VM, and Terraform aborts the clone process with an error message like:

```
Permission check failed (/vms/9500, VM.Clone)
```

This indicates that the service account doesn't have the `VM.Clone` right on the template. The connection works, the token is correct, but Proxmox denies access to the specific action needed for cloning.

In such cases, systematically check the cause: Admins should temporarily assign a full administrator role to the account. This quickly determines whether the rights assignment is the cause, without changing anything in the role structure or ACLs.

```bash
pveum aclmod / -user terraform-prov@pam -role Administrator
```

Then run `terraform plan` and `terraform apply` again.

### Proxmox Cluster Considerations

Proxmox clusters with multiple nodes require identical roles and permissions so that Terraform can distribute resources evenly. The provider's log files show the exact API calls. Proxmox errors in the GUI don't necessarily indicate an abort in Terraform. The state normally shows the valid status.

### Cloud-init Debugging

Errors through Cloud-init can be analyzed via `journalctl` in the started system. Virt-Customize helps to adapt images beforehand and relieve Cloud-init.

### Storage Format Changes

Changes to storage format, for example in ZFS pools, often require a renewed adjustment of the Terraform definition, as the semantic structure of the volume names changes.

### API Token Privilege Separation

Current Proxmox versions separate privileges for API tokens. This default prevents direct queries of the user API, which the widespread Telmate Terraform provider requires. Terraform then reports blocked access despite correct credentials and aborts in the plan step.

The most practical solution is to switch to the actively maintained alternative provider (bpg/proxmox). It uses the same API path but processes privilege separation correctly.

### Logging

With `pm_log_enable` and `pm_log_file`, you can create complete, chronologically sorted log files that contain all API requests.

## Realms and API Access

Proxmox VE fundamentally divides users into two different areas (Realms). The `pve` Realm manages Proxmox-internal accounts and serves to control the management functions within the cluster. The `pam` Realm uses the user accounts of the underlying Linux system.

This separation affects API access, as Proxmox connects certain processes strictly with the internal pve Realm: all tasks around cloning, creating, moving, and configuring virtual machines. Terraform and other automation tools access these functions via the Proxmox API, which is why the service account needs the correct rights and appropriate realm assignment.

A common stumbling block: With API tokens, Proxmox in older and newer versions handles privilege separation differently. Tokens from the pam Realm or tokens with activated privilege separation often lead to a block during cloning, even when all visible rights are present. This combination of realms, roles, ACL paths, token behavior, and storage access often causes errors during cloning, which can often only be resolved through targeted examination of all involved levels.
