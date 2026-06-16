# Self-contained hub when use_existing_hub = false, otherwise look up the live
# Z1 hub. Either way the jump host lands in a management subnet whose NSG blocks
# inbound internet, mirroring the Z1 governance convention.

resource "azurerm_resource_group" "this" {
  name     = "rg-${var.project}"
  location = var.location
  tags     = var.tags
}

# --- Self-contained Z1-style hub (default path) ---
resource "azurerm_virtual_network" "hub" {
  count               = var.use_existing_hub ? 0 : 1
  name                = "vnet-${var.project}-hub"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = ["10.0.0.0/16"]
  tags                = var.tags
}

# Reserved subnets carry the names Azure requires and are sized to minimums so
# the matching services can be activated later without re-addressing.
resource "azurerm_subnet" "bastion" {
  count                = var.use_existing_hub ? 0 : 1
  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.hub[0].name
  address_prefixes     = ["10.0.2.0/26"]
}

resource "azurerm_subnet" "management" {
  count                = var.use_existing_hub ? 0 : 1
  name                 = "snet-management"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.hub[0].name
  address_prefixes     = ["10.0.3.0/24"]
}

resource "azurerm_network_security_group" "management" {
  count               = var.use_existing_hub ? 0 : 1
  name                = "nsg-${var.project}-management"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags

  security_rule {
    name                       = "AllowSshFromAdmin"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.admin_source_cidr
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "DenyAllInbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "management" {
  count                     = var.use_existing_hub ? 0 : 1
  subnet_id                 = azurerm_subnet.management[0].id
  network_security_group_id = azurerm_network_security_group.management[0].id
}

# --- Z1 hook (use_existing_hub = true) ---
data "azurerm_subnet" "existing_management" {
  count                = var.use_existing_hub ? 1 : 0
  name                 = var.existing_management_subnet_name
  virtual_network_name = var.existing_hub_vnet_name
  resource_group_name  = var.existing_hub_resource_group
}

locals {
  management_subnet_id = var.use_existing_hub ? data.azurerm_subnet.existing_management[0].id : azurerm_subnet.management[0].id
}
