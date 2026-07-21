variable "demo_name" {
  description = "Prefix applied to every resource name, in Azure and in Idira."
  type        = string
  default     = "idira-sia-demo"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,32}$", var.demo_name))
    error_message = "demo_name must be 3-32 characters of lowercase letters, digits, or hyphens."
  }
}

variable "azure_location" {
  description = "Azure region to build the demo in."
  type        = string
  default     = "eastus"
}

variable "idsec_auth_method" {
  description = "idsec auth method: identity_service_user (default) or identity."
  type        = string
  default     = "identity_service_user"

  validation {
    condition     = contains(["identity_service_user", "identity"], var.idsec_auth_method)
    error_message = "idsec_auth_method must be identity_service_user or identity."
  }
}

variable "idsec_subdomain" {
  description = "Idira tenant subdomain, e.g. \"acme\" for acme.cyberark.cloud."
  type        = string
}

# --- Networking -------------------------------------------------------------

variable "vnet_cidr" {
  description = "Address space for the demo VNet."
  type        = string
  default     = "10.42.0.0/16"
}

variable "public_subnet_cidr" {
  description = "Subnet holding the SIA connector (needs outbound to the tenant)."
  type        = string
  default     = "10.42.1.0/24"
}

variable "private_subnet_cidr" {
  description = "Subnet holding the target VM. No inbound from internet, no egress."
  type        = string
  default     = "10.42.2.0/24"
}

variable "admin_cidr" {
  description = <<-EOT
    CIDR allowed to SSH to the connector VM for the one-time install. Defaults to
    null, which auto-detects your public IP. Grants no access to the target.
  EOT
  type        = string
  default     = null
}

# --- VMs --------------------------------------------------------------------

variable "connector_vm_size" {
  description = "Size for the SIA connector VM (wants ~2 vCPU / 4 GB)."
  type        = string
  default     = "Standard_B2s"
}

variable "target_vm_size" {
  description = "Size for the demo target VM."
  type        = string
  default     = "Standard_B1s"
}

# --- Idira ------------------------------------------------------------------

variable "sia_ssh_ca_public_key" {
  description = "Pin the SIA SSH CA public key; leave null to fetch it at plan time."
  type        = string
  default     = null
}

variable "policy_role_name" {
  description = "Idira role granted access, resolved to a role id at plan time."
  type        = string
  default     = "Demo Admins"
}

variable "policy_principals" {
  description = "Explicit principals override; null derives a single ROLE from policy_role_name."
  type = list(object({
    id                    = string
    name                  = string
    type                  = string
    source_directory_id   = optional(string)
    source_directory_name = optional(string)
  }))
  default = null
}

variable "policy_target_mode" {
  description = <<-EOT
    How the policy identifies the target: "azure" (match by subscription + resource
    group + VNet + Role tag, via SIA cloud discovery) or "fqdnip" (match the private
    IP directly).

    Defaults to "fqdnip": Azure discovery for VM policies is unverified in this
    tenant, and the private-IP match has no discovery dependency. Switch to "azure"
    once the subscription is confirmed onboarded to SIA.
  EOT
  type        = string
  default     = "fqdnip"

  validation {
    condition     = contains(["azure", "fqdnip"], var.policy_target_mode)
    error_message = "policy_target_mode must be \"azure\" or \"fqdnip\"."
  }
}

variable "ephemeral_username" {
  description = "Local account SIA logs in as; created on the target with no password and no key."
  type        = string
  default     = "demo_user"
}

variable "max_session_duration" {
  description = "Maximum length of a single SIA session, in hours."
  type        = number
  default     = 1
}

variable "idle_time" {
  description = "Idle minutes before SIA terminates the session."
  type        = number
  default     = 10
}

variable "time_zone" {
  description = "Time zone the policy's access window is evaluated in."
  type        = string
  default     = "America/New_York"
}

variable "access_window_days" {
  description = "Days access is permitted, Sunday=0 through Saturday=6."
  type        = set(number)
  default     = [0, 1, 2, 3, 4, 5, 6]
}
