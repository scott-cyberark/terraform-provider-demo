# Fetches the SIA SSH CA the target must trust, and hands it to the target via
# cloud-init -- same approach and the same shared script as the AWS root. See
# aws/ca.tf for the full rationale.

data "external" "sia_ssh_ca" {
  count = var.sia_ssh_ca_public_key == null ? 1 : 0

  program = ["${path.module}/../scripts/get-sia-ssh-ca.py"]
  query   = { subdomain = var.idsec_subdomain }
}

locals {
  sia_ssh_ca_public_key = coalesce(
    var.sia_ssh_ca_public_key,
    one(data.external.sia_ssh_ca[*].result.public_key),
  )
}
