variable "tenancy_ocid" {
  type        = string
  description = "OCI tenant OCID, more details can be found at https://docs.cloud.oracle.com/en-us/iaas/Content/API/Concepts/apisigningkey.htm#five"
}

variable "compartment_ocid" {
  description = "The OCID of the compartment where resources will be created."
  type        = string
}

variable "user_id" {
  type        = string
  description = "OCI user OCID, more details can be found at https://docs.cloud.oracle.com/en-us/iaas/Content/API/Concepts/apisigningkey.htm#five"
}

variable "freeform_tags" {
    type        = map(string)
    description = "A map of freeform tags to apply to resources"
    default     = {}
}

variable "region" {
  description = "The home region where the vault and policies will be created."
  type        = string
  default     = "us-ashburn-1"
}

variable "newrelic_ingest_api_key" {
  type        = string
  sensitive   = true
  description = "The Ingest API key for sending logs to New Relic endpoints"
}

variable "newrelic_user_api_key" {
  type        = string
  sensitive   = true
  description = "The User API key for Linking the OCI Account to the New Relic account"
}

variable "newrelic_common_policy" {
  type        = string
  description = "Common policy name"
  default     = "newrelic-common-policy"
}

variable "dynamic_group_name" {
  type        = string
  description = "Dynamic Group name"
  default     = "newrelic-dynamic-group"
}

variable "newrelic_graphql_endpoint" {
    type        = string
    description = "The New Relic GraphQL endpoint"
    default     = "https://api.newrelic.com/graphql"
}

variable "linkAccount_graphql_query" {
    type        = string
    description = "The GraphQL query to link the OCI account to New Relic"
}