# The shared Idira wiring -- identical module as the AWS root, fed Azure facts.
module "idira" {
  source = "../modules/idira"

  demo_name          = var.demo_name
  policy_role_name   = var.policy_role_name
  policy_principals  = var.policy_principals
  ephemeral_username = var.ephemeral_username

  max_session_duration = var.max_session_duration
  idle_time            = var.idle_time
  time_zone            = var.time_zone
  access_window_days   = var.access_window_days

  # Connector installs onto the public-subnet VM over SSH. ON-PREMISE is the
  # proven install path; the mechanics are SSH regardless of platform type.
  connector_type             = "ON-PREMISE"
  connector_target_machine   = azurerm_public_ip.connector.ip_address
  connector_username         = "azureuser"
  connector_private_key_path = local_sensitive_file.connector_key.filename

  # UNVERIFIED FORMAT: no AZURE_SUBNET identifier exists in the tenant to copy,
  # so this is a best guess -- the subnet's full ARM resource id. If the first
  # apply returns a 400 "Identifier value does not match the required format",
  # this is the value to adjust (candidates: the ARM id below, or a
  # "<vnet-id>/<subnet-name>" composite mirroring AWS's "<vpc>/<subnet>").
  pool_identifier_type  = "AZURE_SUBNET"
  pool_identifier_value = azurerm_subnet.private.id

  policy_target_mode = var.policy_target_mode
  target = {
    subscriptions   = [data.azurerm_client_config.current.subscription_id]
    resource_groups = [azurerm_resource_group.demo.name]
    regions         = [var.azure_location]
    # UNVERIFIED FORMAT: VNet full ARM id vs name -- adjust if azure targeting 400s.
    network_ids  = [azurerm_virtual_network.demo.id]
    tag_key      = "Role"
    tag_value    = azurerm_linux_virtual_machine.target.tags["Role"]
    private_ip   = azurerm_network_interface.target.private_ip_address
    logical_name = var.demo_name
  }

  # The connector install SSHes into the public-subnet VM, so its networking
  # must exist first.
  depends_on = [
    azurerm_subnet_network_security_group_association.public,
    azurerm_linux_virtual_machine.connector,
  ]
}
