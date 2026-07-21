provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

# Credentials are always read from the environment, never from tfvars.
#
#   identity_service_user -> IDSEC_SERVICE_USER + IDSEC_SERVICE_TOKEN
#   identity              -> IDSEC_USERNAME     + IDSEC_SECRET
#
# Service user is the default: it is what Idira recommends for CI/CD, and it
# keeps an MFA prompt from interrupting a live demo. Fall back to "identity"
# with your own admin login if the service user is not yet authorized on the
# OAuth app -- but see the note in variables.tf about pinning the SSH CA key,
# because scripts/get-sia-ssh-ca.py only implements the service-user flow.
provider "idsec" {
  auth_method = var.idsec_auth_method
  subdomain   = var.idsec_subdomain

  # Authenticate fresh on every run instead of reusing a token cached in the OS
  # keyring. Otherwise `make up` caches a token that has expired by the time
  # `make down` runs an hour later, and the stale token returns 401 Unauthorized
  # ("failed to retrieve policy") during the destroy refresh instead of the
  # provider re-authenticating. One extra auth call per command; no downside for
  # a demo that stands up and tears down in separate sessions.
  cache_authentication = false
}
