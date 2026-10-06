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
  default = "centralus"
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

variable "gallery_name" {
  type    = string
  default = ""
}

variable "gallery_image_name" {
  type    = string
  default = "hardened-ubuntu-2204"
}

variable "image_version" {
  type    = string
  default = "1.0.0"
}

variable "build_resource_group" {
  type    = string
  default = ""
}

variable "keep_managed_image" {
  type    = bool
  default = true
}

variable "ssh_allowed_ip" {
  type        = string
  description = "Workstation public /32 allowed to reach the temporary Packer SSH listener."
}

variable "role_path" {
  type    = string
  default = "../ansible/roles"
}

variable "vm_size" {
  type    = string
  default = "Standard_B2s"
}

source "azure-arm" "ubuntu" {
  # Auth comes from the logged-in Azure CLI, so no secret ever lands in a file.
  use_azure_cli_auth = true
  subscription_id    = var.subscription_id

  managed_image_resource_group_name = var.keep_managed_image ? var.image_resource_group : null
  managed_image_name                = var.keep_managed_image ? var.image_name : null
  build_resource_group_name         = var.build_resource_group != "" ? var.build_resource_group : null
  allowed_inbound_ip_addresses      = [var.ssh_allowed_ip]
  encryption_at_host                = true

  dynamic "shared_image_gallery_destination" {
    for_each = var.gallery_name != "" ? [1] : []
    content {
      subscription         = var.subscription_id
      resource_group       = var.image_resource_group
      gallery_name         = var.gallery_name
      image_name           = var.gallery_image_name
      image_version        = var.image_version
      replication_regions  = [var.location]
      storage_account_type = "Standard_LRS"
    }
  }

  os_type         = "Linux"
  image_publisher = "Canonical"
  image_offer     = "0001-com-ubuntu-server-jammy"
  image_sku       = "22_04-lts-gen2"

  location = var.build_resource_group == "" ? var.location : null
  vm_size  = var.vm_size

  azure_tags = {
    project             = "vm-hardening"
    owner               = "jordan"
    source              = "packer"
    cost_center         = "platform"
    environment         = "image-build"
    data_classification = "internal"
  }
}

build {
  name    = "hardened-ubuntu"
  sources = ["source.azure-arm.ubuntu"]

  provisioner "ansible" {
    playbook_file    = "../ansible/site.yml"
    use_proxy        = false
    ansible_env_vars = ["ANSIBLE_ROLES_PATH=${var.role_path}"]
  }

  provisioner "shell" {
    inline            = ["sudo reboot"]
    expect_disconnect = true
  }

  # A boot must preserve the baseline before the image can be published.
  provisioner "shell" {
    pause_before        = "30s"
    start_retry_timeout = "5m"
    script              = "../scripts/check-hardening.sh"
    execute_command     = "sudo -E bash '{{ .Path }}'"
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
