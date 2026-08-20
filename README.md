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

## Palo Alto VM-Series perimeter (opt-in)

The base project hardens the guest OS. This layer adds the network half of
defense-in-depth: a **Palo Alto VM-Series** next-generation firewall in front of
the jump host, with the subnet NSG kept behind it as a second control. It is
gated on `enable_firewall` (default `false`) so the base deploy stays cheap, and
it targets the self-contained hub only (`use_existing_hub = false`).

```
Internet
   |
 untrust NIC (public IP)
   |
 [ Palo Alto VM-Series ]  <- mgmt NIC (public IP) for the console/API
   |
 trust NIC (10.0.6.4)
   |
 snet-management  <- default route 0.0.0.0/0 forced to the trust IP (UDR)
   |
 hardened jump host  (NSG still applied underneath)
```

The jump host's default route is a user-defined route whose next hop is the
firewall trust interface, so all egress is inspected. That is the "vendor
firewall plus cloud-native control" pattern enterprises actually run.

### Deploy the firewall

VM-Series is a marketplace image, so accept its terms once per subscription. The
default SKU is `byol-gen2` (a Gen2 image, required by modern Gen2-only VM sizes):

```bash
az vm image terms accept --publisher paloaltonetworks --offer vmseries-flex --plan byol-gen2
```

Then apply with the firewall enabled:

```bash
cd terraform
terraform apply \
  -var enable_firewall=true \
  -var firewall_admin_password='<StrongPassw0rd!>'
# outputs: firewall_mgmt_ip, firewall_untrust_ip, firewall_console
```

Sizing note: the VM-Series needs 4+ vCPU **and** 3 NICs (mgmt, untrust, trust).
A 4-vCPU size only allows 2 NICs, so the default is `Standard_D8as_v7` (8 vCPU,
Gen2, 4 NICs). Confirm your region and subscription both have capacity and
regional-vCPU quota for it, or override `firewall_vm_size` with a PAN-supported
size that does.

### Configure the policy as code

The appliance is not up during the infra apply, so its security posture lives in
a separate root module (`terraform-panos/`) that runs against the booted
firewall with the official `panos` provider. It sets trust/untrust zones and a
least-privilege egress policy (allow DNS and updates, deny the rest, log both):

```bash
cd terraform-panos
export PANOS_HOSTNAME=<firewall_mgmt_ip>
export PANOS_USERNAME=admin
export PANOS_PASSWORD=<your-admin-password>
terraform init && terraform apply
```

### Firewall cost

The default `Standard_D8as_v7` (8 vCPU) runs roughly $0.35/hour, plus PAYG
bundle licensing if you swap `byol-gen2` for a `bundle*` SKU. Keep it to a short
deploy-demo-destroy window. `terraform destroy` removes the firewall, its NICs,
public IPs, route table, and the added subnets along with the rest.

### Validated live

Deployed and verified end to end on Azure (eastus): the CIS golden image was
baked with Packer, the jump host booted from it into `snet-management`, and the
VM-Series came up as `Standard_D8as_v7` with all three interfaces
(mgmt/untrust/trust). The jump host's route table confirmed the default route
`0.0.0.0/0 -> 10.0.6.4` (VirtualAppliance, the firewall trust IP), so egress is
forced through the firewall. Torn down clean afterward.

Two gotchas surfaced and are now baked into the config:

- **SSH key must be RSA.** The managed-image VM path rejects `ssh-ed25519`
  ("Only RSA SSH keys are supported"). Generate an RSA key and point
  `ssh_public_key_path` at it: `ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa_vmlab`.
- **Image generation must match the VM size.** The Gen1 `byol` image will not
  boot on Gen2-only sizes (the `D*_v6/v7` families); use `byol-gen2` there.

## Hardening notes (production deltas)

- For zero-public-IP access, deploy the **Azure Bastion** service into `AzureBastionSubnet` and set `enable_public_ip = false`. Skipped here because Bastion runs about $4.50/day, which does not suit a deploy-demo-destroy budget.
- Promote the managed image to a **Shared Image Gallery** for versioning and multi-region replication.
- Run a full **Lynis** or CIS-benchmark scan in CI against the baked image for a scored audit artifact.
