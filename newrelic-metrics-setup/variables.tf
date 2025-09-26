variable "tenancy_ocid" {
  type        = string
  description = "OCI tenant OCID, more details can be found at https://docs.cloud.oracle.com/en-us/iaas/Content/API/Concepts/apisigningkey.htm#five.Do not modify."
}

variable "compartment_ocid" {
  type        = string
  description = "The OCID of the compartment where resources will be created. Do not modify."
}

variable "nr_prefix" {
  type        = string
  description = "The prefix for naming resources in this module."
}

variable "region" {
  type        = string
  description = "The name of the OCI region where these resources will be deployed."
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

variable "newrelic_account_id" {
  type        = string
  sensitive   = false
  description = "The New Relic account ID for sending metrics to New Relic endpoints"
}

variable "create_vcn" {
  type        = bool
  default     = true
  description = "Variable to create virtual network for the setup. True by default"
}

variable "function_subnet_id" {
  type        = string
  default     = ""
  description = "The OCID of the subnet to be used for the function app. If create_vcn is set to true, that will take precedence"
}

variable "payload_link" {
  type        = string
  description = "The link to the payload for the connector hubs."
}
