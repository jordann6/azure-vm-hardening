packer {
  required_plugins {
    azure = {
      source  = "github.com/hashicorp/azure"
      version = ">= 2.1.0"
    }
    ansible = {
      source  = "github.com/hashicorp/ansible"
      version = ">= 1.1.0"
    }
  }
}

variable "subscription_id" {
  type        = string
  description = "Azure subscription to build the image in."
}

variable "location" {
  type    = string
  default = "eastus"
}

variable "image_resource_group" {
  type        = string
  default     = "rg-vmhardening-images"
  description = "Resource group that holds the captured managed image. Must exist."
}

variable "image_name" {
  type    = string
  default = "img-hardened-ubuntu-2204"
}

source "azure-arm" "ubuntu" {
  # Auth comes from the logged-in Azure CLI, so no secret ever lands in a file.
  use_azure_cli_auth = true
  subscription_id    = var.subscription_id

  managed_image_resource_group_name = var.image_resource_group
  managed_image_name                = var.image_name

  os_type         = "Linux"
  image_publisher = "Canonical"
  image_offer     = "0001-com-ubuntu-server-jammy"
  image_sku       = "22_04-lts-gen2"

  location = var.location
  vm_size  = "Standard_B2s"

  azure_tags = {
    project = "vm-hardening"
    owner   = "jordan"
    source  = "packer"
  }
}

build {
  name    = "hardened-ubuntu"
  sources = ["source.azure-arm.ubuntu"]

  provisioner "ansible" {
    playbook_file = "../ansible/site.yml"
    galaxy_file   = "../ansible/requirements.yml"
    use_proxy     = false
  }

  # Generalize the image so Azure can deploy clean instances from it.
  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} sudo -E sh '{{ .Path }}'"
    inline = [
      "/usr/sbin/waagent -force -deprovision+user",
      "export HISTSIZE=0",
      "sync",
    ]
    inline_shebang = "/bin/sh -x"
  }
}
