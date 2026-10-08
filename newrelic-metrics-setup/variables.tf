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
  description = "The endpoint to hit for sending the metrics. Varies by region [US|EU|JP]"
  validation {
    condition     = contains(["US", "EU", "JP"], var.newrelic_endpoint)
    error_message = "Valid values for var: newrelic_endpoint are (US, EU, JP)."
  }
}

variable "newrelic_account_id" {
  type        = string
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

variable "function_image" {
  type        = string
  default     = "docker.io/newrelic/beyond-oci-metric-function:latest"
  description = "Public image for the metrics function. The stack copies it into a private Container Registry repository in your tenancy and runs the function from there. Re-applying the stack picks up a new image pushed under the same tag."
}

variable "current_user_ocid" {
  type        = string
  default     = ""
  description = "OCID of the user running the stack. Populated by Resource Manager; used to create the auth token that pushes the function image to Container Registry."
}

variable "registry_username" {
  type        = string
  default     = ""
  description = "Container Registry username, without the tenancy namespace. Leave empty to use the user running the stack. Set it for users in a non-default identity domain (<domain_name>/<username>)."
}

variable "registry_auth_token" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Existing auth token for pushing to Container Registry. Leave empty to have the stack create one for the user running it (OCI allows two auth tokens per user)."
}
