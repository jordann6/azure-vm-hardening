output "jumphost_name" {
  value = azurerm_linux_virtual_machine.jumphost.name
}

output "jumphost_private_ip" {
  value = azurerm_network_interface.jumphost.private_ip_address
}

output "jumphost_public_ip" {
  value = var.enable_public_ip ? azurerm_public_ip.jumphost[0].ip_address : null
}

output "ssh_command" {
  value = var.enable_public_ip ? "ssh ${var.admin_username}@${azurerm_public_ip.jumphost[0].ip_address}" : "no public IP (use az vm run-command or Bastion)"
}

output "image_id" {
  value = data.azurerm_image.hardened.id
}

output "firewall_mgmt_ip" {
  value       = local.firewall_enabled ? azurerm_public_ip.fw_mgmt[0].ip_address : null
  description = "Public IP for the VM-Series management UI/SSH (null when the firewall is disabled)."
}

output "firewall_untrust_ip" {
  value       = local.firewall_enabled ? azurerm_public_ip.fw_untrust[0].ip_address : null
  description = "Public IP on the firewall untrust (data plane) interface."
}

output "firewall_console" {
  value       = local.firewall_enabled ? "https://${azurerm_public_ip.fw_mgmt[0].ip_address} (default admin/admin, change on first login)" : "firewall disabled"
  description = "How to reach the VM-Series management console after boot."
}
