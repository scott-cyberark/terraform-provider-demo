locals {
  common_tags = {
    Demo      = "idira-sia"
    ManagedBy = "terraform"
  }

  # The connector is installed over SSH from wherever Terraform runs, so that
  # address needs to reach port 22 on the connector. Auto-detect unless pinned.
  admin_cidr = coalesce(
    var.admin_cidr,
    "${chomp(data.http.my_ip.response_body)}/32",
  )
}

data "http" "my_ip" {
  url = "https://checkip.amazonaws.com"
}

resource "azurerm_resource_group" "demo" {
  name     = "${var.demo_name}-rg"
  location = var.azure_location
  tags     = local.common_tags
}

resource "azurerm_virtual_network" "demo" {
  name                = "${var.demo_name}-vnet"
  address_space       = [var.vnet_cidr]
  location            = azurerm_resource_group.demo.location
  resource_group_name = azurerm_resource_group.demo.name
  tags                = local.common_tags
}

# --- Subnets ----------------------------------------------------------------

resource "azurerm_subnet" "public" {
  name                 = "${var.demo_name}-public"
  resource_group_name  = azurerm_resource_group.demo.name
  virtual_network_name = azurerm_virtual_network.demo.name
  address_prefixes     = [var.public_subnet_cidr]
}

resource "azurerm_subnet" "private" {
  name                 = "${var.demo_name}-private"
  resource_group_name  = azurerm_resource_group.demo.name
  virtual_network_name = azurerm_virtual_network.demo.name
  address_prefixes     = [var.private_subnet_cidr]
}

# --- Connector NSG: SSH in from the operator, outbound to the tenant --------

resource "azurerm_network_security_group" "connector" {
  name                = "${var.demo_name}-connector-nsg"
  location            = azurerm_resource_group.demo.location
  resource_group_name = azurerm_resource_group.demo.name
  tags                = local.common_tags

  security_rule {
    name                       = "ssh-from-operator"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = local.admin_cidr
    destination_address_prefix = "*"
  }
  # Outbound to the internet (the Idira tenant) is allowed by Azure's default rules.
}

resource "azurerm_subnet_network_security_group_association" "public" {
  subnet_id                 = azurerm_subnet.public.id
  network_security_group_id = azurerm_network_security_group.connector.id
}

# --- Target NSG: reachable only from the connector subnet, no egress --------

resource "azurerm_network_security_group" "target" {
  name                = "${var.demo_name}-target-nsg"
  location            = azurerm_resource_group.demo.location
  resource_group_name = azurerm_resource_group.demo.name
  tags                = local.common_tags

  # Only inbound: SSH from the connector subnet. (Azure's default DenyAllInBound
  # already blocks the internet; this + the VNet deny below leave 22-from-connector
  # as the single way in.)
  security_rule {
    name                       = "ssh-from-connector"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.public_subnet_cidr
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "deny-other-vnet-in"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }

  # No egress. Overrides Azure's default AllowInternetOutBound. This is the
  # equivalent of the AWS private subnet's empty route table.
  security_rule {
    name                       = "deny-internet-out"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "Internet"
  }
}

resource "azurerm_subnet_network_security_group_association" "private" {
  subnet_id                 = azurerm_subnet.private.id
  network_security_group_id = azurerm_network_security_group.target.id
}
