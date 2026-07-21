provider "azurerm" {
  features {}
  # Authentication and the active subscription come from your `az login` session.
  # Select the subscription first with: az account set --subscription <id|name>.
}

data "azurerm_client_config" "current" {}

# Same idsec configuration as the AWS root -- credentials from the environment,
# fresh auth each run.
provider "idsec" {
  auth_method          = var.idsec_auth_method
  subdomain            = var.idsec_subdomain
  cache_authentication = false
}
