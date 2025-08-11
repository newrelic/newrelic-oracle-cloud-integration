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
  default     = "newrelic-staging-metric-api"
  description = "The endpoint to hit for sending the metrics. Varies by region [US|EU]"
  validation {
    condition     = contains(["newrelic-staging-metric-api", "newrelic-metric-api", "newrelic-eu-metric-api"], var.newrelic_endpoint)
    error_message = "Valid values for var: newrelic_endpoint are (newrelic-staging-metric-api, newrelic-staging-vortex-metric-api, newrelic-metric-api, newrelic-eu-metric-api)."
  }
}

variable "home_secret_ocid" {
    type        = string
    description = "The OCID of the secret in the home region where the New Relic Ingest API key is stored."
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

variable "metrics_namespaces" {
  type        = list(string)
  description = "The list of namespaces to send metrics for, within their respective compartments. Remove any namespaces where metrics should not be sent."
  default = [
    "oci_apigateway",
    "oci_autonomous_database",
    "oci_blockstore",
    "oci_compute",
    "oci_compute_infrastructure_health",
    "oci_compute_instance_health",
    "oci_computeagent",
    "oci_database",
    "oci_database_cluster",
    "oci_faas",
    "oci_healthchecks",
    "oci_internet_gateway",
    "oci_lbaas",
    "oci_logging",
    "oci_nat_gateway",
    "oci_nlb",
    "oci_nlb_extended",
    "oci_nosql",
    "oci_objectstorage",
    "oci_oke",
    "oci_postgresql",
    "oci_service_connector_hub",
    "oci_service_gateway",
    "oci_vcn",
    "oci_vcnip",
    "oci_vmi_resource_utilization"
  ]
}
