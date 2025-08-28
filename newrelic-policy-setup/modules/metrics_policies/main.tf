# ------ Metrics Only Resources -----

terraform {
  required_version = ">= 1.2.0"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "5.46.0"
    }
  }
}

provider "oci" {
  alias        = "home"
  tenancy_ocid = var.tenancy_ocid
  user_ocid    = var.user_id
  region       = var.region
}

resource "oci_identity_policy" "nr_metrics_policy" {
  compartment_id = var.tenancy_ocid
  description    = "[DO NOT REMOVE] Policy to have read metrics for newrelic integration"
  name           = var.newrelic_metrics_policy
  statements     = [
    "Allow dynamic-group ${var.dynamic_group_name} to read metrics in tenancy"
  ]
  defined_tags  = {}
  freeform_tags = var.freeform_tags
}