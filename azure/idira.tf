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

  # The pool identifier must describe the target the same way the policy does:
  #
  #   fqdnip mode -> GENERAL_CIDR_BLOCK over the private subnet. The connector
  #     reaches the target by IP; no cloud workspace is involved. AZURE_SUBNET
  #     would instead tag the pool as an Azure cloud workspace, which SIA can only
  #     resolve if the subscription is onboarded -- and an un-onboarded one makes
  #     policy creation fail with "unsupported workspace type or missing resource".
  #
  #   azure mode -> AZURE_SUBNET (the subnet's ARM id, which the API accepts).
  #     Requires the subscription onboarded to SIA cloud discovery.
  pool_identifier_type  = var.policy_target_mode == "azure" ? "AZURE_SUBNET" : "GENERAL_CIDR_BLOCK"
  pool_identifier_value = var.policy_target_mode == "azure" ? azurerm_subnet.private.id : var.private_subnet_cidr

  policy_target_mode = var.policy_target_mode
  target = {
    subscriptions = [data.azurerm_client_config.current.subscription_id]
    # SIA stores resource groups and VNets as full ARM resource paths, not names
    # -- confirmed against a working policy in the tenant. The .id attributes give
    # exactly that (/subscriptions/<sub>/resourceGroups/<rg>[/providers/...]).
    resource_groups = [azurerm_resource_group.demo.id]
    regions         = [var.azure_location]
    network_ids     = [azurerm_virtual_network.demo.id]
    tag_key         = "Role"
    tag_value       = azurerm_linux_virtual_machine.target.tags["Role"]
    private_ip      = azurerm_network_interface.target.private_ip_address
    logical_name    = var.demo_name
  }

  # The connector install SSHes into the public-subnet VM, so its networking
  # must exist first.
  depends_on = [
    azurerm_subnet_network_security_group_association.public,
    azurerm_linux_virtual_machine.connector,
  ]
}
