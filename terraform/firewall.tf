# ── Palo Alto VM-Series perimeter (opt-in) ───────────────────────────────────
# The base project hardens the guest OS. This layer adds the network half of
# defense-in-depth: a Palo Alto VM-Series next-generation firewall in front of
# the jump host, with the subnet NSG kept behind it as a second control.
#
# Everything here is gated on enable_firewall so the base deploy stays cheap.
# It targets the self-contained hub only (use_existing_hub = false); against a
# live Z1 hub the firewall belongs in the hub's own AzureFirewallSubnet-adjacent
# NVA subnets, which the landing-zone repo owns.
#
# VM-Series needs three NICs: management, untrust (public side), and trust
# (toward the protected subnet). The trust NIC is the next hop for the jump
# host's default route, so all egress is inspected.

locals {
  firewall_enabled = var.enable_firewall && !var.use_existing_hub
  fw_count         = local.firewall_enabled ? 1 : 0
}

# --- Firewall subnets (added to the self-contained hub) ---
resource "azurerm_subnet" "fw_mgmt" {
  count                = local.fw_count
  name                 = "snet-fw-mgmt"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.hub[0].name
  address_prefixes     = ["10.0.4.0/24"]
}

resource "azurerm_subnet" "fw_untrust" {
  count                = local.fw_count
  name                 = "snet-fw-untrust"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.hub[0].name
  address_prefixes     = ["10.0.5.0/24"]
}

resource "azurerm_subnet" "fw_trust" {
  count                = local.fw_count
  name                 = "snet-fw-trust"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.hub[0].name
  address_prefixes     = ["10.0.6.0/24"]
}

# --- Public IPs (management access + untrust data plane) ---
resource "azurerm_public_ip" "fw_mgmt" {
  count               = local.fw_count
  name                = "pip-${var.project}-fw-mgmt"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_public_ip" "fw_untrust" {
  count               = local.fw_count
  name                = "pip-${var.project}-fw-untrust"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

# --- NICs ---
resource "azurerm_network_interface" "fw_mgmt" {
  count               = local.fw_count
  name                = "nic-${var.project}-fw-mgmt"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags

  ip_configuration {
    name                          = "mgmt"
    subnet_id                     = azurerm_subnet.fw_mgmt[0].id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.fw_mgmt[0].id
  }
}

resource "azurerm_network_interface" "fw_untrust" {
  count                 = local.fw_count
  name                  = "nic-${var.project}-fw-untrust"
  location              = var.location
  resource_group_name   = azurerm_resource_group.this.name
  ip_forwarding_enabled = true
  tags                  = var.tags

  ip_configuration {
    name                          = "untrust"
    subnet_id                     = azurerm_subnet.fw_untrust[0].id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.fw_untrust[0].id
  }
}

resource "azurerm_network_interface" "fw_trust" {
  count                 = local.fw_count
  name                  = "nic-${var.project}-fw-trust"
  location              = var.location
  resource_group_name   = azurerm_resource_group.this.name
  ip_forwarding_enabled = true
  tags                  = var.tags

  ip_configuration {
    name                          = "trust"
    subnet_id                     = azurerm_subnet.fw_trust[0].id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.firewall_trust_ip
  }
}

# --- VM-Series firewall ---
# The plan/source_image_reference pair points at the Palo Alto marketplace
# offer. Accept the image terms once per subscription before applying:
#   az vm image terms accept --publisher paloaltonetworks \
#     --offer vmseries-flex --plan <fw_image_sku>
resource "azurerm_virtual_machine" "vmseries" {
  count                        = local.fw_count
  name                         = "vm-${var.project}-vmseries"
  location                     = var.location
  resource_group_name          = azurerm_resource_group.this.name
  vm_size                      = var.firewall_vm_size
  primary_network_interface_id = azurerm_network_interface.fw_mgmt[0].id

  network_interface_ids = [
    azurerm_network_interface.fw_mgmt[0].id,
    azurerm_network_interface.fw_untrust[0].id,
    azurerm_network_interface.fw_trust[0].id,
  ]

  # PAYG bundle licensing. Switch to a byol SKU + auth code to use BYOL.
  plan {
    name      = var.firewall_image_sku
    publisher = "paloaltonetworks"
    product   = "vmseries-flex"
  }

  storage_image_reference {
    publisher = "paloaltonetworks"
    offer     = "vmseries-flex"
    sku       = var.firewall_image_sku
    version   = "latest"
  }

  storage_os_disk {
    name              = "osdisk-${var.project}-vmseries"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  os_profile {
    computer_name  = "vmseries"
    admin_username = var.firewall_admin_username
    admin_password = var.firewall_admin_password
  }

  os_profile_linux_config {
    disable_password_authentication = false
  }

  delete_os_disk_on_termination = true
  tags                          = var.tags

  lifecycle {
    precondition {
      condition     = var.firewall_admin_password != null && var.firewall_admin_password != ""
      error_message = "Set firewall_admin_password when enable_firewall = true."
    }
  }
}

# --- Force jump-host egress through the firewall's trust interface ---
resource "azurerm_route_table" "protected" {
  count               = local.fw_count
  name                = "rt-${var.project}-protected"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags

  route {
    name                   = "default-via-firewall"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = var.firewall_trust_ip
  }
}

resource "azurerm_subnet_route_table_association" "protected" {
  count          = local.fw_count
  subnet_id      = azurerm_subnet.management[0].id
  route_table_id = azurerm_route_table.protected[0].id
}
