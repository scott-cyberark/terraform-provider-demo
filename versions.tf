terraform {
  required_version = ">= 1.5"

  required_providers {
    idsec = {
      source  = "cyberark/idsec"
      version = ">= 0.7"
    }
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
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
