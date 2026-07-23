# Shared Idira/tenant wiring, parameterized by cloud-specific facts the roots
# pass in. This module holds every idsec_* resource; the roots hold the cloud
# infrastructure. It is where the connector, pool, and policy are created once
# and reused by both the AWS and Azure roots.

# --- Naming / identity ------------------------------------------------------

variable "demo_name" {
  type        = string
  description = "Prefix for the network, pool, and policy names in the tenant."
}

variable "policy_role_name" {
  type        = string
  description = "Idira role granted access, resolved to a role id via idsec_identity_role."
}

variable "policy_principals" {
  type = list(object({
    id                    = string
    name                  = string
    type                  = string
    source_directory_id   = optional(string)
    source_directory_name = optional(string)
  }))
  default     = null
  description = "Explicit principals override. Null derives a single ROLE from policy_role_name."
}

variable "ephemeral_username" {
  type        = string
  description = "Local account SIA logs in as (created on the target by the root)."
}

# --- Session conditions -----------------------------------------------------

variable "max_session_duration" {
  type    = number
  default = 1
}

variable "idle_time" {
  type    = number
  default = 10
}

variable "time_zone" {
  type    = string
  default = "America/New_York"
}

variable "access_window_days" {
  type    = set(number)
  default = [0, 1, 2, 3, 4, 5, 6]
}

# --- Connector --------------------------------------------------------------

variable "connector_type" {
  type        = string
  description = "Platform type for the connector install (ON-PREMISE, AWS, AZURE, GCP)."
  default     = "ON-PREMISE"
}

variable "connector_target_machine" {
  type        = string
  description = "Public IP of the connector host to install onto over SSH."
}

variable "connector_username" {
  type        = string
  description = "SSH username on the connector host (ec2-user, azureuser, ...)."
}

variable "connector_private_key_path" {
  type        = string
  description = "Path to the private key file used to reach the connector host."
}

# --- Pool identifiers -------------------------------------------------------

variable "pool_identifiers" {
  description = <<-EOT
    One or more identifiers telling SIA which targets this connector pool serves.
    A pool can carry several: e.g. a GENERAL_CIDR_BLOCK for IP-based reach plus an
    AZURE_VNET so the pool is also associated with the cloud network.

    Types: GENERAL_CIDR_BLOCK, GENERAL_FQDN, GENERAL_HOSTNAME, AWS_ACCOUNT_ID,
    AWS_VPC, AWS_SUBNET, AZURE_SUBSCRIPTION, AZURE_VNET, AZURE_SUBNET, GCP_*.
    Value formats differ per type -- Azure wants full ARM resource paths.
  EOT
  type = list(object({
    type  = string
    value = string
  }))
}

# --- Policy target ----------------------------------------------------------

variable "policy_target_mode" {
  type        = string
  description = "How the policy matches the target: aws | azure | fqdnip."

  validation {
    condition     = contains(["aws", "azure", "fqdnip"], var.policy_target_mode)
    error_message = "policy_target_mode must be aws, azure, or fqdnip."
  }
}

variable "target" {
  description = "Normalized facts about the target, used to build the policy's target block."
  type = object({
    account_ids     = optional(list(string)) # aws
    subscriptions   = optional(list(string)) # azure
    resource_groups = optional(list(string)) # azure
    regions         = optional(list(string))
    network_ids     = optional(list(string)) # vpc_ids (aws) / vnet_ids (azure)
    tag_key         = optional(string, "Role")
    tag_value       = optional(string)
    private_ip      = optional(string) # fqdnip
    logical_name    = optional(string) # fqdnip
  })
}
