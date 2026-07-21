terraform {
  required_version = ">= 1.5"

  # Cloud-agnostic: only the idsec provider. Each root configures it (subdomain,
  # auth, cache) and this module inherits that configuration.
  required_providers {
    idsec = {
      source  = "cyberark/idsec"
      version = ">= 0.7"
    }
  }
}
