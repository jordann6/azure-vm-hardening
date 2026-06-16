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
