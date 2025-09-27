variable "tenancy_ocid" {
  type        = string
  description = "OCI tenant OCID, more details can be found at https://docs.cloud.oracle.com/en-us/iaas/Content/API/Concepts/apisigningkey.htm#five"
}

variable "current_user_ocid" {
  type        = string
  description = "The OCID of the current user executing the terraform script. Do not modify."
}

variable "compartment_ocid" {
  type        = string
  description = "The OCID of the compartment where resources will be created."
}

variable "region" {
  type        = string
  description = "OCI Region as documented at https://docs.cloud.oracle.com/en-us/iaas/Content/General/Concepts/regions.htm"
}

variable "newrelic_endpoint" {
  type        = string
  default     = "US"
  description = "The endpoint to hit for sending the metrics. Varies by region [US|EU]"
  validation {
    condition     = contains(["US", "EU"], var.newrelic_endpoint)
    error_message = "Valid values for var: newrelic_endpoint are (US, EU)."
  }
}

variable "newrelic_ingest_api_key" {
  type        = string
  sensitive   = true
  default     = ""
  description = "The Ingest API key for sending metrics to New Relic endpoints"
}

variable "newrelic_user_api_key" {
  type        = string
  sensitive   = true
  description = "The User API key for Linking the OCI Account to the New Relic account"
}

variable "newrelic_account_id" {
  type        = string
  description = "The New Relic account ID for sending metrics to New Relic endpoints"
}

variable "link_account_name" {
  type        = string
  default     = ""
  description = "The name to assign to the linked account in New Relic"
}

variable "linked_account_id" {
  type        = string
  default     = null
  description = "The provider ID for New Relic integration with OCI"
}

variable "policy_stack" {
  type        = string
  description = "A string indicating which parts of the stack to deploy. Use comma-separated values from METRICS, LOGS, COMMON."
}

variable "client_id" {
  type        = string
  sensitive   = true
  default     = ""
  description = "Client ID for API access"
}

variable "client_secret" {
  type        = string
  sensitive   = true
  default     = ""
  description = "Client Secret for API access"
}

variable "oci_domain_url" {
  type        = string
  default     = ""
  description = "OCI domain URL"
}

variable "svc_user_name" {
  type        = string
  sensitive   = true
  default     = ""
  description = "Service user name for OCI access"
}

