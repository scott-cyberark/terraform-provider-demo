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
      # Must agree with the targets block below: AWS-attribute matching is an
      # "AWS" location, direct IP matching is "FQDN/IP".
      location_type = var.policy_target_mode == "aws" ? "AWS" : "FQDN/IP"
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

  # Two ways to scope the policy to our one instance, selected by
  # var.policy_target_mode. Exactly one block is non-null.
  #
  # "aws" (default): match by AWS attributes -- our VPC plus the instance's own
  #   Role tag. SIA resolves this through the account's cloud-workspace
  #   discovery, so the policy never hardcodes an address. The tag matters: the
  #   connector shares this VPC, so VPC alone would also grant access to it.
  #
  # "fqdnip": match the instance's private IP directly. No cloud discovery
  #   dependency -- the reliable fallback if AWS discovery has not caught up.
  targets = {
    aws_resource = var.policy_target_mode == "aws" ? {
      # Account + region + VPC key the match to this exact workspace, the way SIA
      # discovers instances; the Role tag then selects the target within it (the
      # connector shares this VPC, so VPC alone would include it).
      account_ids = [data.aws_caller_identity.current.account_id]
      regions     = [var.aws_region]
      vpc_ids     = [aws_vpc.demo.id]
      tags = [
        {
          key = "Role"
          # Sourced from the instance's own tag so the two cannot drift.
          value = [aws_instance.target.tags["Role"]]
        }
      ]
    } : null

    fqdnip_resource = var.policy_target_mode == "fqdnip" ? {
      ip_rules = [
        {
          operator     = "EXACTLY"
          ip_addresses = [aws_instance.target.private_ip]
          logical_name = idsec_cmgr_network.demo.name
        }
      ]
    } : null
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
