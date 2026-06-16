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
