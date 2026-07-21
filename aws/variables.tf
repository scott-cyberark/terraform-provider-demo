variable "demo_name" {
  description = "Prefix applied to every resource name, in AWS and in Idira. Change it to run two demos side by side."
  type        = string
  default     = "idira-sia-demo"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,32}$", var.demo_name))
    error_message = "demo_name must be 3-32 characters of lowercase letters, digits, or hyphens."
  }
}

variable "aws_region" {
  description = "AWS region to build the demo environment in. Matches the configured CLI default so the proof commands in `make proof` line up."
  type        = string
  default     = "us-east-2"
}

variable "idsec_auth_method" {
  description = <<-EOT
    How the provider authenticates.

    "identity_service_user" (default) reads IDSEC_SERVICE_USER and
    IDSEC_SERVICE_TOKEN. Preferred: non-interactive, no MFA prompt mid-demo.

    "identity" reads IDSEC_USERNAME and IDSEC_SECRET -- your own login. Use it
    if the service user is not yet authorized on the OAuth app. If you do, also
    set sia_ssh_ca_public_key, because scripts/get-sia-ssh-ca.py implements only
    the service-user flow and will fail under user auth.
  EOT
  type        = string
  default     = "identity_service_user"

  validation {
    condition     = contains(["identity_service_user", "identity"], var.idsec_auth_method)
    error_message = "idsec_auth_method must be identity_service_user or identity."
  }
}

variable "idsec_subdomain" {
  description = <<-EOT
    Idira tenant subdomain, e.g. "acme" for acme.cyberark.cloud. Used by
    scripts/get-sia-ssh-ca.py to reach https://<subdomain>.dpa.cyberark.cloud.
  EOT
  type        = string
}

# --- Networking -------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block for the demo VPC."
  type        = string
  default     = "10.42.0.0/16"
}

variable "public_subnet_cidr" {
  description = "Public subnet holding the SIA connector. Needs egress to reach the Idira tenant."
  type        = string
  default     = "10.42.1.0/24"
}

variable "private_subnet_cidr" {
  description = "Private subnet holding the target server. No IGW route, no NAT, no egress."
  type        = string
  default     = "10.42.2.0/24"
}

variable "admin_cidr" {
  description = <<-EOT
    CIDR allowed to SSH to the *connector* instance. The idsec_sia_access_connector
    resource installs the connector over SSH from wherever Terraform runs, so this
    must include your current public IP. Defaults to null, which auto-detects it.

    Note this grants no access to the target server -- the target accepts SSH from
    the connector's security group only.
  EOT
  type        = string
  default     = null
}

# --- Instances --------------------------------------------------------------

variable "connector_instance_type" {
  description = "Instance type for the SIA connector. The connector wants ~2 vCPU / 4 GB; smaller types make the install flaky."
  type        = string
  default     = "t3.medium"
}

variable "target_instance_type" {
  description = "Instance type for the demo target server."
  type        = string
  default     = "t3.micro"
}

# --- Idira ------------------------------------------------------------------

variable "sia_ssh_ca_public_key" {
  description = <<-EOT
    The SIA SSH CA public key, baked into the target's cloud-init so the target
    trusts certificates SIA issues.

    Leave null to fetch it at plan time via scripts/get-sia-ssh-ca.py. Set it to
    pin the value and make the demo independent of a live API call -- the CA is
    stable per tenant and only changes on an explicit rotation. Get it with:
      ./scripts/get-sia-ssh-ca.py | python3 -c 'import json,sys;print(json.load(sys.stdin)["public_key"])'
  EOT
  type        = string
  default     = null
}

variable "policy_role_name" {
  description = <<-EOT
    Name of the Idira role granted access by the VM policy. Resolved to a role ID
    at plan time via the idsec_identity_role data source, so the config stays
    readable and portable across tenants.

    Set this to a role that exists in your tenant, via terraform.tfvars. The
    default is a placeholder and will not resolve as-is.

    Whoever presents the demo must be a member of this role, or the connect step
    will fail. Verify membership before presenting.
  EOT
  type        = string
  default     = "Demo Admins"
}

variable "policy_principals" {
  description = <<-EOT
    Full override for who the policy grants access to. Leave null to derive a
    single ROLE principal from policy_role_name, which is what the demo does.

    Set this only when you need something policy_role_name cannot express --
    multiple principals, or USER/GROUP types (which also require
    source_directory_id and source_directory_name).
  EOT
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
    How the VM policy identifies the target.

    "aws" (default): match by AWS attributes -- the demo VPC plus the instance's
    Role tag. Attribute-based and decoupled from the address, but SIA resolves it
    through the account's cloud-workspace discovery, so it depends on that
    integration covering this VPC and can lag for a just-created instance.

    "fqdnip": match the instance's private IP directly. No discovery dependency;
    the reliable fallback, and what has been proven end to end. Flip to this in
    terraform.tfvars if AWS targeting does not resolve during a live demo.
  EOT
  type        = string
  default     = "aws"

  validation {
    condition     = contains(["aws", "fqdnip"], var.policy_target_mode)
    error_message = "policy_target_mode must be \"aws\" or \"fqdnip\"."
  }
}

variable "ephemeral_username" {
  description = <<-EOT
    The local account SIA logs in as. For Linux SSH, SIA authenticates as an
    existing local user and presents a short-lived certificate -- the ephemeral
    part is the certificate, not the OS account (unlike RDP, where SIA can
    provision an ephemeral OS user).

    target.tf creates this account with no password and no SSH key, so the only
    way in is a certificate SIA signs for a single session. It must match the
    policy's ssh_profile.username, which it does -- both read this variable.
  EOT
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
  description = "Days the policy permits access, where Sunday=0 through Saturday=6."
  type        = set(number)
  default     = [0, 1, 2, 3, 4, 5, 6]
}

# Hour bounds (from_hour/to_hour) are intentionally omitted: the SDK validates
# them as HH:MM:SS client-side while the policy API demands HH:MM, so no value
# satisfies both. The module leaves them unset. Day-of-week is still enforced.
