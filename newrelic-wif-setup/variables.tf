variable "tenancy_ocid" {
  type        = string
  description = "OCI tenant OCID. See https://docs.cloud.oracle.com/en-us/iaas/Content/API/Concepts/apisigningkey.htm#five"
}

variable "current_user_ocid" {
  type        = string
  description = "The OCID of the current user executing the stack. Do not modify — auto-populated by ORM."
}

variable "region" {
  type        = string
  description = "OCI region. Do not modify — auto-populated by ORM."
}

variable "compartment_ocid" {
  type        = string
  description = "Compartment OCID. Do not modify — auto-populated by ORM."
}

variable "identity_domain_name" {
  type        = string
  default     = "Default"
  description = "Name of the OCI Identity Domain to use. Usually 'Default' unless you have custom domains."
}

variable "newrelic_region" {
  type        = string
  default     = "US"
  description = "New Relic region: US, EU, or JP."
  validation {
    condition     = contains(["US", "EU", "JP"], var.newrelic_region)
    error_message = "newrelic_region must be US, EU, or JP."
  }
}

variable "trust_type" {
  type        = string
  default     = "UPST"
  description = "OCI WIF trust type. UPST (default, service-user impersonation) or RPST (claim-based). Use RPST for multi-account customers or those hitting OCI IAM policy limits."
  validation {
    condition     = contains(["UPST", "RPST"], var.trust_type)
    error_message = "trust_type must be UPST or RPST."
  }
}

variable "newrelic_account_id" {
  type        = string
  default     = ""
  description = "New Relic account ID. Required when trust_type = RPST."
}

# Name for the Identity Propagation Trust created in OCI Identity Domain.
# Hidden in ORM form — default is correct for most customers. Expose if needed for
# multi-integration tenancies where trust names must be unique per Identity Domain.
variable "trust_name" {
  type        = string
  default     = "newrelic-trust-setup"
  description = "Name of the Identity Propagation Trust created in OCI Identity Domain. Must be unique per Identity Domain if you have multiple NR integrations."
}

# Internal — not exposed in ORM form
variable "resource_prefix" {
  type        = string
  default     = "newrelic"
  description = "Prefix for all created OCI resources."
}

variable "activate_oauth_apps" {
  type        = bool
  default     = true
  description = "Whether to activate the OAuth applications immediately on creation."
}
