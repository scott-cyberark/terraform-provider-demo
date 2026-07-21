# --- Target VM --------------------------------------------------------------
# The SSH CA it trusts is fetched in ca.tf (local.sia_ssh_ca_public_key).
#
# Azure VMs cannot be fully keyless -- azurerm_linux_virtual_machine requires an
# admin_ssh_key. We generate one and DO NOT write the private key anywhere, so no
# usable key persists: the only way in is a certificate SIA signs per session.

resource "tls_private_key" "target" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "azurerm_network_interface" "target" {
  name                = "${var.demo_name}-target-nic"
  location            = azurerm_resource_group.demo.location
  resource_group_name = azurerm_resource_group.demo.name
  tags                = local.common_tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.private.id
    private_ip_address_allocation = "Dynamic"
    # No public_ip_address_id -- the target has no public address.
  }
}

resource "azurerm_linux_virtual_machine" "target" {
  name                = "${var.demo_name}-target"
  resource_group_name = azurerm_resource_group.demo.name
  location            = azurerm_resource_group.demo.location
  size                = var.target_vm_size
  admin_username      = "azureuser"

  network_interface_ids = [azurerm_network_interface.target.id]

  # Required by Azure, but the private key is discarded (see above). SIA logs in
  # as demo_user via certificate, not as azureuser.
  admin_ssh_key {
    username   = "azureuser"
    public_key = tls_private_key.target.public_key_openssh
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

  # Same CA-install + demo_user provisioning as AWS. Ubuntu's ssh unit is
  # "ssh.service" (AL2023 uses "sshd.service"), so the restart tries both.
  custom_data = base64encode(<<-EOT
    #!/bin/bash
    set -euo pipefail

    ca_file=/etc/ssh/SIA_ssh_public_CA.pub
    sshd_config=/etc/ssh/sshd_config
    login_user='${var.ephemeral_username}'

    printf '%s\n' '${local.sia_ssh_ca_public_key}' > "$ca_file"
    chmod 644 "$ca_file"
    chown root:root "$ca_file"

    if ! grep -q '^TrustedUserCAKeys' "$sshd_config"; then
      echo "TrustedUserCAKeys $ca_file" >> "$sshd_config"
    fi

    if ! id -u "$login_user" >/dev/null 2>&1; then
      useradd -m -s /bin/bash "$login_user"
      echo "$login_user ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$login_user"
      chmod 440 "/etc/sudoers.d/$login_user"
    fi

    cp "$sshd_config" "$sshd_config.bak"
    if sshd -t; then
      systemctl restart ssh 2>/dev/null || systemctl restart sshd
    else
      mv "$sshd_config.bak" "$sshd_config"
      echo "sshd config test failed; reverted" >&2
      exit 1
    fi

    cat > /etc/motd <<'BANNER'

      ${var.demo_name} -- demo target (Azure)

      No public IP. Reachable only from the SIA connector subnet.
      This account has no password and no SSH key.
      You are here on a short-lived, single-session certificate.

    BANNER
  EOT
  )

  tags = merge(local.common_tags, {
    Name = "${var.demo_name}-target"
    Role = "demo-target"
  })
}
