terraform {
  required_version = ">= 1.5"

  required_providers {
    idsec = {
      source  = "cyberark/idsec"
      version = ">= 0.7"
    }
    # Pinned to v3: it infers the subscription from your `az login` session,
    # whereas v4 requires subscription_id to be set explicitly.
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.116"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.4"
    }
    external = {
      source  = "hashicorp/external"
      version = ">= 2.3"
    }
    http = {
      source  = "hashicorp/http"
      version = ">= 3.4"
    }
  }
}
