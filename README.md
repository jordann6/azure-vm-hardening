# Azure VM Hardening

An immutable golden-image pipeline that bakes a CIS-style hardening baseline into an Ubuntu 22.04 image, then deploys a jump host from that image into a Z1-style management subnet. The role is tested in CI with Molecule before it is ever baked, so the image is provably hardened before a single VM boots.

This fills the VM config-management gap in an otherwise serverless and Kubernetes portfolio. The toolchain is **Packer + Ansible + Molecule**; **Terraform** still owns every cloud resource and Ansible does in-OS configuration only, keeping the boundary clean.

## Architecture

![Architecture](docs/architecture.png)

```
Ansible role (cis_baseline)
  -> tested by Molecule (docker driver: converge, verify, idempotence) in GitHub Actions
        |
Packer (azure-arm builder)
  -> transient Ubuntu 22.04 build VM
  -> runs the Ansible role as a provisioner   (the immutable bake)
  -> captures a managed image: img-hardened-ubuntu-2204
        |
Terraform
  -> deploys a jump host from the image into snet-management (10.0.3.0/24)
  -> NSG blocks inbound internet, allows SSH from your IP only
        |
Validate hardening on the live host -> terraform destroy + delete image
```

## Why this shape

- **Immutable image, not config drift.** Hardening is applied once at bake time and frozen into the image. The running jump host carries no provisioner, so every instance is identical and reproducible.
- **Tested before baked.** Molecule converges the role in a container and asserts the result on every push, so a broken control fails CI rather than shipping in an image.
- **Clean tool boundary.** Terraform provisions cloud resources; Ansible only touches in-OS state. No Ansible reaches into Azure and no Terraform shells into the OS.

## Hardening baseline (`cis_baseline` role)

| Area | Controls |
|---|---|
| **sshd** | No root login, no password auth, strong ciphers/MACs/KEX, MaxAuthTries, LoginGraceTime, forwarding disabled |
| **auditd** | Installed and enabled with a baseline ruleset (identity, logins, sudoers, time-change), rules made immutable |
| **fail2ban** | sshd jail with configurable ban/find/retry windows |
| **sysctl** | IP forwarding/redirects off, rp_filter, tcp syncookies, ASLR, dmesg/kptr restrict, suid_dumpable off |
| **PAM / login.defs** | pwquality complexity, password aging, restrictive umask |
| **filesystem** | Unused filesystem modules (cramfs, freevxfs, jffs2, hfs, hfsplus, udf) blacklisted |

Every control is a toggle in `defaults/main.yml`, so the role stays reusable beyond the jump host.

## Z1 landing-zone coupling

By default the repo provisions its own Z1-style hub VNet (10.0.0.0/16) with correctly named and sized reserved subnets (`AzureBastionSubnet`, `snet-management`) so it demos standalone. Set `use_existing_hub = true` to instead drop the jump host into a live [azure-landing-zone](https://github.com/jordann6/azure-landing-zone) hub via Terraform data sources.

Note on subnet placement: the jump host lives in `snet-management`, not `AzureBastionSubnet`. That reserved subnet is for the Azure Bastion managed service only and cannot host a normal VM. Bastion is documented below as the production access path.

## Prerequisites

- Azure CLI logged in, Packer >= 1.10, Terraform >= 1.6, Ansible >= 2.16
- An SSH keypair (default `~/.ssh/id_ed25519.pub`)
- A resource group for the image and the azurerm state backend (see `backend.tf`):
  ```bash
  az group create -n rg-vmhardening-images -l eastus
  ```

## Build the image

```bash
cd packer
packer init .
packer build -var "subscription_id=$(az account show --query id -o tsv)" hardened-ubuntu.pkr.hcl
```

This bakes the role into `img-hardened-ubuntu-2204`. The build VM is transient and destroyed automatically once the image is captured.

## Deploy the jump host

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # set admin_source_cidr to your IP
terraform init
terraform apply
```

## Validate

```bash
# Works with or without a public IP (uses az vm run-command):
./scripts/validate-hardening.sh rg-vmhardening vm-vmhardening-jumphost
```

Confirm sshd rejects root and password auth, auditd and fail2ban are active, the sysctl values are applied, and the filesystem modules are blacklisted. With a public IP you can also `ssh azureadmin@<public-ip>` from the allowed source.

## Destroy

```bash
cd terraform && terraform destroy
# The image is not in Terraform state, so remove it explicitly:
./scripts/destroy-image.sh rg-vmhardening-images img-hardened-ubuntu-2204
```

## Cost and teardown risk

- **Packer build VM** (Standard_B2s, ~10-15 min) plus image storage: a few cents.
- **Jump host** (Standard_B1s) while demoing: roughly $0.01/hour.
- **Total deploy-demo-destroy, same day: under ~$1.**
- Teardown risk: the managed image is not part of the jump-host Terraform state, so `terraform destroy` leaves it behind. `scripts/destroy-image.sh` removes it. If you set `use_existing_hub = true`, remember the Z1 landing zone is a separate destroy.

## Hardening notes (production deltas)

- For zero-public-IP access, deploy the **Azure Bastion** service into `AzureBastionSubnet` and set `enable_public_ip = false`. Skipped here because Bastion runs about $4.50/day, which does not suit a deploy-demo-destroy budget.
- Promote the managed image to a **Shared Image Gallery** for versioning and multi-region replication.
- Run a full **Lynis** or CIS-benchmark scan in CI against the baked image for a scored audit artifact.
