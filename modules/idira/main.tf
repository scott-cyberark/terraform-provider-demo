# Resolve the role by name rather than pinning an opaque id.
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

  # location_type must agree with the target block below.
  location_type = {
    aws    = "AWS"
    azure  = "Azure"
    fqdnip = "FQDN/IP"
  }[var.policy_target_mode]

  # Tag filter, if a tag value is supplied. AWS discovery surfaces instance tags,
  # so the tag pins the policy to exactly the target. Azure discovery does not
  # currently surface VM tags for policy matching, so the Azure root passes a null
  # tag_value and scopes by resource group + VNet + region instead (matching how a
  # working policy is built in the tenant). An empty list means "no tag filter".
  target_tags = var.target.tag_value == null ? [] : [
    {
      key   = var.target.tag_key
      value = [var.target.tag_value]
    }
  ]
}

# --- Connector Management: network -> pool -> identifier --------------------

resource "idsec_cmgr_network" "demo" {
  name = var.demo_name
}

resource "idsec_cmgr_pool" "demo" {
  name                 = "${var.demo_name}-pool"
  description          = "Connector pool for the ${var.demo_name} environment, managed by Terraform."
  assigned_network_ids = [idsec_cmgr_network.demo.network_id]
}

# Scopes the pool to the exact subnet the root created. The value format is
# cloud-specific and set by the root (e.g. AWS_SUBNET is "<vpc-id>/<subnet-id>").
resource "idsec_cmgr_pool_identifier" "target_subnet" {
  pool_id = idsec_cmgr_pool.demo.pool_id
  type    = var.pool_identifier_type
  value   = var.pool_identifier_value
}

# --- Connector installation -------------------------------------------------

resource "idsec_sia_access_connector" "demo" {
  connector_type    = var.connector_type
  connector_os      = "linux"
  connector_pool_id = idsec_cmgr_pool.demo.pool_id

  target_machine   = var.connector_target_machine
  username         = var.connector_username
  private_key_path = var.connector_private_key_path

  # The install starts SSHing before cloud-init has sshd ready; retries absorb
  # that race, which is the single most likely thing to fail mid-demo.
  retry_count = 20
  retry_delay = 15

  # Lets a re-run clean up a connector orphaned by an interrupted destroy.
  force_delete = true
}

# --- Access policy ----------------------------------------------------------

resource "idsec_policy_vm" "demo" {
  metadata = {
    name        = var.demo_name
    description = "Least-privilege SSH access to the ${var.demo_name} target, managed by Terraform."

    policy_entitlement = {
      target_category = "VM"
      location_type   = local.location_type
    }

    status = {
      status = "Active"
    }

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
    }
    max_session_duration = var.max_session_duration
    idle_time            = var.idle_time
  }

  # Exactly one block is non-null, chosen by policy_target_mode.
  targets = {
    aws_resource = var.policy_target_mode == "aws" ? {
      account_ids = var.target.account_ids
      regions     = var.target.regions
      vpc_ids     = var.target.network_ids
      tags        = local.target_tags
    } : null

    azure_resource = var.policy_target_mode == "azure" ? {
      subscriptions   = var.target.subscriptions
      resource_groups = var.target.resource_groups
      regions         = var.target.regions
      vnet_ids        = var.target.network_ids
      tags            = local.target_tags
    } : null

    fqdnip_resource = var.policy_target_mode == "fqdnip" ? {
      ip_rules = [
        {
          operator     = "EXACTLY"
          ip_addresses = [var.target.private_ip]
          logical_name = var.target.logical_name
        }
      ]
    } : null
  }

  behavior = {
    ssh_profile = {
      # Existing local account SIA logs in as, presenting a short-lived cert.
      # The root creates this account with no password and no key.
      username = var.ephemeral_username
    }
  }

  # Only enforceable once a connector in the pool can reach the target.
  depends_on = [
    idsec_sia_access_connector.demo,
    idsec_cmgr_pool_identifier.target_subnet,
  ]
}
