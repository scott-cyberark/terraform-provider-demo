provider "azurerm" {
  features {}
  # Authentication and the active subscription come from your `az login` session.
  # Select the subscription first with: az account set --subscription <id|name>.

  # Don't try to auto-register every Azure resource provider at startup -- a
  # restricted/lab account can't register RPs at the subscription level and the
  # bulk attempt 403s. The demo only uses Microsoft.Network and Microsoft.Compute,
  # which are already registered on essentially every subscription. (v3 argument;
  # v4 renamed this to resource_provider_registrations = "none".)
  skip_provider_registration = true
}

data "azurerm_client_config" "current" {}

# Same idsec configuration as the AWS root -- credentials from the environment,
# fresh auth each run.
provider "idsec" {
  auth_method          = var.idsec_auth_method
  subdomain            = var.idsec_subdomain
  cache_authentication = false
}
