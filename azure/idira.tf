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

  # What the pool serves. In fqdnip mode the connector reaches the target by IP,
  # so a GENERAL_CIDR_BLOCK over the private subnet is what the policy matches on
  # -- but we also attach the VNet so the pool is associated with the Azure
  # network itself, not just a bare IP range. In azure mode the subnet identifier
  # carries that association on its own.
  #
  # Azure identifier values are full ARM resource paths (the .id attributes).
  pool_identifiers = var.policy_target_mode == "azure" ? [
    {
      type  = "AZURE_SUBNET"
      value = azurerm_subnet.private.id
    },
    ] : [
    {
      type  = "GENERAL_CIDR_BLOCK"
      value = var.private_subnet_cidr
    },
    {
      type  = "AZURE_VNET"
      value = azurerm_virtual_network.demo.id
    },
  ]

  policy_target_mode = var.policy_target_mode
  target = {
    subscriptions = [data.azurerm_client_config.current.subscription_id]
    # SIA stores resource groups and VNets as full ARM resource paths, not names
    # -- confirmed against a working policy in the tenant. The .id attributes give
    # exactly that (/subscriptions/<sub>/resourceGroups/<rg>[/providers/...]).
    resource_groups = [azurerm_resource_group.demo.id]
    regions         = [var.azure_location]
    network_ids     = [azurerm_virtual_network.demo.id]
    # No tag filter on Azure: SIA's Azure discovery does not surface VM tags for
    # policy matching (a tag-filtered policy fails "missing resource" while the
    # same filter works on AWS). Scope by resource group + VNet + region instead
    # -- this RG is dedicated to the demo, and only the target trusts the SIA CA,
    # so the connector VM in the same RG is not actually cert-reachable.
    tag_value    = null
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
