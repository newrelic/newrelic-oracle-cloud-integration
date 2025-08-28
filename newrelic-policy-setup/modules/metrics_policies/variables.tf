variable "tenancy_ocid" {
  type        = string
  description = "OCI tenant OCID, more details can be found at https://docs.cloud.oracle.com/en-us/iaas/Content/API/Concepts/apisigningkey.htm#five"
}

variable "region" {
  description = "The home region where the vault and policies will be created."
  type        = string
  default     = "us-ashburn-1"
}

variable "newrelic_metrics_policy" {
  type        = string
  description = "The name of the policy for metrics"
  default     = "newrelic-metrics-policy"
}

variable "dynamic_group_name" {
  type        = string
  description = "Dynamic group name"
  default     = "newrelic-dynamic-group"
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