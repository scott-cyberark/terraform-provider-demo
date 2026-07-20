# Resolve the role by name rather than pinning an opaque ID, so the config reads
# as intent and moves between tenants without edits.
data "idsec_identity_role" "demo" {
  count = var.policy_principals == null ? 1 : 0

  role_name = var.policy_role_name
}

locals {
  policy_principals = var.policy_principals != null ? var.policy_principals : [
    {
      id                    = one(data.idsec_identity_role.demo[*].role_id)
      name                  = var.policy_role_name
      type                  = "ROLE"
      source_directory_id   = null
      source_directory_name = null
    }
  ]
}

# The access policy. This is the resource to linger on when presenting: the
# infrastructure above and the entitlement below are created by the same apply,
# from the same state, in the same commit.

resource "idsec_policy_vm" "demo" {
  metadata = {
    name        = var.demo_name
    description = "Least-privilege SSH access to the ${var.demo_name} target, managed by Terraform."

    policy_entitlement = {
      target_category = "VM"
      location_type   = "FQDN/IP"
    }

    status = {
      status = "Active"
    }

    # Unbounded. Set from_time/to_time for a policy that expires on its own --
    # a good follow-up question to invite from the room.
    time_frame = {
      from_time = null
      to_time   = null
    }

    policy_tags = ["terraform", "demo"]
    time_zone   = var.time_zone
  }

  principals = local.policy_principals

  conditions = {
    access_window = {
      days_of_the_week = var.access_window_days
      from_hour        = var.access_window_from_hour
      to_hour          = var.access_window_to_hour
    }
    max_session_duration = var.max_session_duration
    idle_time            = var.idle_time
  }

  # Scoped to the one instance Terraform just created, by its private address.
  # Nothing else in the VPC is in scope -- not the connector, not a future
  # instance in the same subnet.
  targets = {
    fqdnip_resource = {
      ip_rules = [
        {
          operator     = "EXACTLY"
          ip_addresses = [aws_instance.target.private_ip]
          logical_name = idsec_cmgr_network.demo.name
        }
      ]
    }
  }

  behavior = {
    ssh_profile = {
      # The existing local account SIA logs in as, presenting a short-lived
      # certificate. target.tf creates this same account with no password and no
      # SSH key, so the certificate is the only way in. Both read the same
      # variable, so the names cannot drift.
      username = var.ephemeral_username
    }
  }

  # The policy is only enforceable once a connector in the pool can actually
  # reach the target, so don't create it before the connector is registered.
  depends_on = [
    idsec_sia_access_connector.demo,
    idsec_cmgr_pool_identifier.private_subnet,
  ]
}
