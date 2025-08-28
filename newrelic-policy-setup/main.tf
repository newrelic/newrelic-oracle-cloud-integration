terraform {
  required_version = ">= 1.2.0"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "5.46.0"
    }
  }
}

module "common_policies" {
  count   = var.create_common_stack ? 1 : 0
  source = "./modules/common_policies"

  # Variables for common policies
  tenancy_ocid = var.tenancy_ocid
  compartment_ocid = var.compartment_ocid
  newrelic_account_id = var.newrelic_account_id
  newrelic_ingest_api_key = var.newrelic_license_key
  newrelic_user_api_key      = var.newrelic_user_api_key
  newrelic_common_policy = var.newrelic_common_policy
  dynamic_group_name = var.dynamic_group_name
  current_user_ocid = ""
  linkAccount_graphql_query = ""
  user_id = ""
}

module "logging_policies" {
  count                = var.create_logs_stack ? 1 : 0
  source               = "./modules/logging_policies"

  # Variables for logging policies
  tenancy_ocid         = var.tenancy_ocid
  region               = var.region
  newrelic_logs_policy = var.newrelic_logs_policy
  dynamic_group_name   = var.dynamic_group_name
  user_id              = data.oci_identity_user.current_user.user_id
}

module "metrics_policies" {
  count              = local.is_home_region && var.create_metrics_stack ? 1 : 0
  source             = "./modules/metrics_policies"

  # Variables for metrics policies
  tenancy_ocid       = var.tenancy_ocid
  region             = var.region
  dynamic_group_name = var.dynamic_group_name
  user_id            = data.oci_identity_user.current_user.user_id
}