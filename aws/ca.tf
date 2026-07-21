# --- SIA SSH certificate authority ------------------------------------------
#
# The target must trust the CA that SIA signs session certificates with. The
# provider's idsec_sia_ssh_public_key resource does this by SSHing into the
# target from wherever Terraform runs -- which would mean opening the target to
# inbound SSH from the operator and defeating the demo's premise.
#
# The same CA is available from the API, so we fetch it once here and hand it to
# the target through cloud-init. The target is provisioned without ever being
# reachable from outside the VPC. The fetch script is shared by both cloud roots.

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
