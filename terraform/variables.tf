variable "project" {
  type    = string
  default = "vmhardening"
}

variable "location" {
  type    = string
  default = "eastus"
}

# --- Golden image (built by Packer) ---
variable "image_resource_group" {
  type        = string
  default     = "rg-vmhardening-images"
  description = "Resource group holding the Packer-built managed image."
}

variable "image_name" {
  type    = string
  default = "img-hardened-ubuntu-2204"
}

# --- Z1 landing-zone hook ---
variable "use_existing_hub" {
  type        = bool
  default     = false
  description = "When true, deploy the jump host into an existing Z1 hub VNet via data sources instead of provisioning a self-contained hub."
}

variable "existing_hub_vnet_name" {
  type    = string
  default = "vnet-alz-hub"
}

variable "existing_hub_resource_group" {
  type    = string
  default = "rg-alz-hub"
}

variable "existing_management_subnet_name" {
  type    = string
  default = "snet-management"
}

# --- Jump host ---
variable "admin_username" {
  type    = string
  default = "azureadmin"
}

variable "ssh_public_key_path" {
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
  description = "Public key injected into the jump host for SSH."
}

variable "vm_size" {
  type    = string
  default = "Standard_B1s"
}

variable "enable_public_ip" {
  type        = bool
  default     = true
  description = "Attach a temporary public IP for the demo. NSG still restricts SSH to admin_source_cidr only."
}

variable "admin_source_cidr" {
  type        = string
  description = "Your public IP in CIDR form (e.g. 203.0.113.4/32). The only source allowed to SSH."
}

variable "tags" {
  type = map(string)
  default = {
    project = "vm-hardening"
    owner   = "jordan"
  }
}

# --- Palo Alto VM-Series perimeter (opt-in) ---
variable "enable_firewall" {
  type        = bool
  default     = false
  description = "Deploy a Palo Alto VM-Series in front of the jump host. Only takes effect on the self-contained hub (use_existing_hub = false). Adds real cost, so it is off by default."
}

variable "firewall_vm_size" {
  type        = string
  default     = "Standard_D8as_v7"
  description = "VM-Series needs 4+ vCPU AND 3 NICs (mgmt/untrust/trust); a 4-vCPU size only allows 2 NICs, so an 8-vCPU size is required. Older PAN-listed sizes (D3_v2, DS3_v2) are quota/capacity-restricted on many subs; D8as_v7 (Gen2, 4 NICs) is broadly available. Override if PAN pins you to a specific SKU."
}

variable "firewall_image_sku" {
  type        = string
  default     = "byol-gen2"
  description = "Marketplace SKU for the paloaltonetworks/vmseries-flex offer. byol-gen2 is a Gen2 image, required by modern Gen2-only VM sizes (D*_v6). Use byol/bundle1/bundle2 for Gen1 sizes. Accept image terms first: az vm image terms accept."
}

variable "firewall_trust_ip" {
  type        = string
  default     = "10.0.6.4"
  description = "Static private IP of the firewall trust NIC. Used as the next hop for the jump host's default route."
}

variable "firewall_admin_username" {
  type    = string
  default = "paadmin"
}

variable "firewall_admin_password" {
  type        = string
  default     = null
  sensitive   = true
  description = "Bootstrap admin password for the VM-Series. Required only when enable_firewall = true."
}
