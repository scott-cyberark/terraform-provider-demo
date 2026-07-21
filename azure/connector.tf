# --- Connector SSH keypair --------------------------------------------------
# Generated per-apply and destroyed with everything else.

resource "tls_private_key" "connector" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# The connector install needs the private key on disk.
resource "local_sensitive_file" "connector_key" {
  content         = tls_private_key.connector.private_key_pem
  filename        = "${path.module}/keys/${var.demo_name}-connector.pem"
  file_permission = "0600"
}

# --- Connector host ---------------------------------------------------------

resource "azurerm_public_ip" "connector" {
  name                = "${var.demo_name}-connector-pip"
  location            = azurerm_resource_group.demo.location
  resource_group_name = azurerm_resource_group.demo.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.common_tags
}

resource "azurerm_network_interface" "connector" {
  name                = "${var.demo_name}-connector-nic"
  location            = azurerm_resource_group.demo.location
  resource_group_name = azurerm_resource_group.demo.name
  tags                = local.common_tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.public.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.connector.id
  }
}

resource "azurerm_linux_virtual_machine" "connector" {
  name                = "${var.demo_name}-connector"
  resource_group_name = azurerm_resource_group.demo.name
  location            = azurerm_resource_group.demo.location
  size                = var.connector_vm_size
  admin_username      = "azureuser"

  network_interface_ids = [azurerm_network_interface.connector.id]

  admin_ssh_key {
    username   = "azureuser"
    public_key = tls_private_key.connector.public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  tags = merge(local.common_tags, { Name = "${var.demo_name}-connector" })
}
