# --- SIA SSH certificate authority ------------------------------------------
#
# The target must trust the CA that SIA signs session certificates with. The
# provider's idsec_sia_ssh_public_key resource does this by SSHing into the
# target from wherever Terraform runs -- which would mean opening the target to
# inbound SSH from the operator and defeating the demo's premise.
#
# The same CA is available from the API, so we fetch it once here and hand it to
# the target through cloud-init. The target is provisioned without ever being
# reachable from outside the VPC.

data "external" "sia_ssh_ca" {
  count = var.sia_ssh_ca_public_key == null ? 1 : 0

  program = ["${path.module}/scripts/get-sia-ssh-ca.py"]
  query   = { subdomain = var.idsec_subdomain }
}

locals {
  sia_ssh_ca_public_key = coalesce(
    var.sia_ssh_ca_public_key,
    one(data.external.sia_ssh_ca[*].result.public_key),
  )
}

# --- Target server ----------------------------------------------------------

resource "aws_instance" "target" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = var.target_instance_type
  subnet_id     = aws_subnet.private.id

  vpc_security_group_ids      = [aws_security_group.target.id]
  associate_public_ip_address = false

  # No key_name. There is no SSH key for this box anywhere -- not on your laptop,
  # not in AWS. The only way in is a certificate SIA mints at connect time.

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
    encrypted   = true
  }

  # Two steps, both matching how CyberArk documents Linux SIA access:
  #
  # 1. Install the SSH CA. Mirrors the paths and validate-before-restart guard
  #    of the idsec SDK's own install script, so this box is indistinguishable
  #    from one provisioned the supported way.
  #
  # 2. Create the login account. For Linux SSH, SIA authenticates "as an
  #    existing local user of the target machine" -- the ephemeral part is the
  #    short-lived certificate, not an ephemeral OS user (that is the RDP model).
  #    So the account named in the policy's ssh_profile.username must exist, or
  #    sshd rejects the certificate with "[none publickey]". We create it with
  #    no password and no authorized_keys: the only way in is a certificate SIA
  #    signs for a single session.
  user_data = <<-EOT
    #!/bin/bash
    set -euo pipefail

    ca_file=/etc/ssh/SIA_ssh_public_CA.pub
    sshd_config=/etc/ssh/sshd_config
    login_user='${var.ephemeral_username}'

    printf '%s\n' '${local.sia_ssh_ca_public_key}' > "$ca_file"
    chmod 644 "$ca_file"
    chown root:root "$ca_file"

    if ! grep -q '^TrustedUserCAKeys' "$sshd_config"; then
      echo "TrustedUserCAKeys $ca_file" >> "$sshd_config"
    fi

    # The account SIA logs in as. useradd leaves the password locked, so there
    # is no password login; we add no SSH key, so there is no key login either.
    # Passwordless sudo lets the session demonstrate real privileged access.
    if ! id -u "$login_user" >/dev/null 2>&1; then
      useradd -m -s /bin/bash "$login_user"
      echo "$login_user ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$login_user"
      chmod 440 "/etc/sudoers.d/$login_user"
    fi

    # Never restart into a broken config -- roll back instead.
    cp "$sshd_config" "$sshd_config.bak"
    if sshd -t; then
      systemctl restart sshd
    else
      mv "$sshd_config.bak" "$sshd_config"
      echo "sshd config test failed; reverted" >&2
      exit 1
    fi

    cat > /etc/motd <<'BANNER'

      ${var.demo_name} -- demo target

      No public IP. No inbound rule except the SIA connector.
      This account has no password and no SSH key.
      You are here on a short-lived, single-session certificate.

    BANNER
  EOT

  # Re-provision if the CA rotates.
  user_data_replace_on_change = true

  tags = {
    Name = "${var.demo_name}-target"
    Role = "demo-target"
  }
}
