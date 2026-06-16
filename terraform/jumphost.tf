# Jump host deployed from the Packer-built hardened image. No provisioners run
# here: the host boots already hardened, which is the whole point of the
# immutable-image pattern.

data "azurerm_image" "hardened" {
  name                = var.image_name
  resource_group_name = var.image_resource_group
}

resource "azurerm_public_ip" "jumphost" {
  count               = var.enable_public_ip ? 1 : 0
  name                = "pip-${var.project}-jumphost"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_network_interface" "jumphost" {
  name                = "nic-${var.project}-jumphost"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = local.management_subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = var.enable_public_ip ? azurerm_public_ip.jumphost[0].id : null
  }
}

resource "azurerm_linux_virtual_machine" "jumphost" {
  name                  = "vm-${var.project}-jumphost"
  location              = var.location
  resource_group_name   = azurerm_resource_group.this.name
  size                  = var.vm_size
  admin_username        = var.admin_username
  network_interface_ids = [azurerm_network_interface.jumphost.id]
  source_image_id       = data.azurerm_image.hardened.id
  tags                  = var.tags

  admin_ssh_key {
    username   = var.admin_username
    public_key = file(var.ssh_public_key_path)
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
}
