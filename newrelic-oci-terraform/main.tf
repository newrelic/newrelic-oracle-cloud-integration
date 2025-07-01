terraform {
  required_version = ">= 1.2.0"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "5.46.0"
    }
  }
}

# Variables
provider "oci" {
  alias        = "home"
  tenancy_ocid = var.tenancy_ocid
  user_ocid    = data.oci_identity_user.current_user.user_id
  region       = var.region
}

data "oci_identity_user" "current_user" {
  user_id = var.current_user_ocid
}

data "oci_identity_region_subscriptions" "subscriptions" {
  tenancy_id = var.tenancy_ocid
}

data "oci_identity_tenancy" "current_tenancy" {
  tenancy_id = var.tenancy_ocid
}

data "oci_identity_policies" "existing_policies" {
  compartment_id = var.compartment_ocid
}

data "oci_identity_dynamic_groups" "existing_dynamic_groups" {
  compartment_id = var.tenancy_ocid
}

data "oci_functions_applications" "existing_functions_apps" {
  compartment_id = var.compartment_ocid
}

locals {
  home_region = data.oci_identity_region_subscriptions.subscriptions.region_subscriptions[0].region_name
  is_home_region = var.region == local.home_region
  freeform_tags = {
    newrelic-terraform = "true"
  }
  policy_not_exists = length([
    for policy in data.oci_identity_policies.existing_policies.policies : policy.name
    if policy.name == var.newrelic_metrics_policy
  ]) == 0
  dynamic_group_not_exists = length([
    for dg in data.oci_identity_dynamic_groups.existing_dynamic_groups.dynamic_groups : dg.name
    if dg.name == var.dynamic_group_name
  ]) == 0
  # Names for the network infra
  vcn_name        = "newrelic-metrics-vcn"
  nat_gateway     = "${local.vcn_name}-natgateway"
  service_gateway = "${local.vcn_name}-servicegateway"
  subnet          = "${local.vcn_name}-private-subnet"
}

resource "oci_kms_vault" "newrelic_vault" {
  compartment_id = var.compartment_ocid
  display_name   = "newrelic-vault"
  vault_type     = "DEFAULT"
  freeform_tags  = local.freeform_tags
}

resource "oci_kms_key" "newrelic_key" {
  compartment_id = var.compartment_ocid
  display_name   = "newrelic-key"
  key_shape {
    algorithm = "AES"
    length    = 32
  }
  management_endpoint = oci_kms_vault.newrelic_vault.management_endpoint
  freeform_tags       = local.freeform_tags
}

resource "oci_vault_secret" "api_key" {
  compartment_id = var.compartment_ocid
  vault_id       = oci_kms_vault.newrelic_vault.id
  key_id         = oci_kms_key.newrelic_key.id
  secret_name    = "NewRelicAPIKey"
  secret_content {
    content_type = "BASE64"
    content      = base64encode(var.newrelic_api_key)
  }
  freeform_tags = local.freeform_tags
}

#Resource for the dynamic group
resource "oci_identity_dynamic_group" "nr_serviceconnector_group" {
  count          = local.is_home_region ? 1 : 0
  compartment_id = var.tenancy_ocid
  description    = "[DO NOT REMOVE] Dynamic group for service connector"
  matching_rule  = "All {resource.type = 'serviceconnector'}"
  name           = var.dynamic_group_name
  defined_tags   = {}
  freeform_tags  = local.freeform_tags
}

#Resource for the policy
resource "oci_identity_policy" "nr_metrics_policy" {
  count          = local.is_home_region ? 1 : 0
  depends_on     = [oci_identity_dynamic_group.nr_serviceconnector_group]
  compartment_id = var.tenancy_ocid
  description    = "[DO NOT REMOVE] Policy to have any connector hub read from monitoring source and write to a target function"
    name         = var.newrelic_metrics_policy
  statements = [
    "Allow dynamic-group ${var.dynamic_group_name} to read metrics in tenancy",
    "Allow dynamic-group ${var.dynamic_group_name} to use fn-function in tenancy",
    "Allow dynamic-group ${var.dynamic_group_name} to use fn-invocation in tenancy",
    "Allow dynamic-group ${var.dynamic_group_name} to manage stream-family in tenancy",
    "Allow group ${var.dynamic_group_name} to manage repos in tenancy",
    "Allow group ${var.dynamic_group_name} to read metrics in tenancy",
    "Allow dynamic-group ${var.dynamic_group_name} to read secret-bundles in tenancy",
  ]
  defined_tags  = {}
  freeform_tags = local.freeform_tags
}

#Resource for the function application
resource "oci_functions_application" "metrics_function_app" {
  depends_on     = [oci_identity_policy.nr_metrics_policy]
  compartment_id = var.compartment_ocid
  config = {
    "FORWARD_TO_NR"                = "False"
    "LOGGING_ENABLED"              = "True"
    "NR_METRIC_ENDPOINT"           = var.newrelic_endpoint
    "TENANCY_OCID"                 = var.compartment_ocid
    "SECRET_OCID"                  = oci_vault_secret.api_key.id
    "VAULT_REGION"                 = var.region
  }
  defined_tags               = {}
  display_name               = var.newrelic_function_app
  freeform_tags              = local.freeform_tags
  network_security_group_ids = []
  shape                      = var.function_app_shape
  subnet_ids = [
    module.vcn[0].subnet_id[local.subnet], # Corrected reference
  ]
}

#Resource for the function
resource "oci_functions_function" "metrics_function" {
  depends_on = [oci_functions_application.metrics_function_app]

  application_id = oci_functions_application.metrics_function_app.id
  display_name   = "${oci_functions_application.metrics_function_app.display_name}-metrics-function"
  memory_in_mbs  = "256"

  defined_tags  = {}
  freeform_tags = local.freeform_tags
  image         = "${var.region}.ocir.io/axg8w2haraxp/public-newrelic-repo:latest"
}

#Resource for the service connector hub-1
resource "oci_sch_service_connector" "nr_service_connector" {
  depends_on     = [oci_functions_function.metrics_function]
  compartment_id = var.compartment_ocid
  display_name   = var.connector_hub_name

  # Source Configuration with Monitoring
  source {
    kind = "monitoring"

    monitoring_sources {
      compartment_id = var.compartment_ocid
      namespace_details {
        kind = "selected"

        dynamic "namespaces" {
          for_each = var.metrics_namespaces
          content {
            namespace = namespaces.value
            metrics {
              kind = "all" // Adjust based on actual needs, possibly sum, mean, count
            }
          }
        }
      }
    }
  }

  # Target Configuration with Streaming
  target {
    #Required
    kind = "functions"

    #Optional
    batch_size_in_kbs = 5000
    batch_time_in_sec = 60
    compartment_id    = var.compartment_ocid
    function_id       = oci_functions_function.metrics_function.id
  }

  # Optional tags and additional metadata
  description   = "Service Connector from Monitoring to Streaming"
  defined_tags  = {}
  freeform_tags = {}
}


module "vcn" {
  source                   = "oracle-terraform-modules/vcn/oci"
  version                  = "3.6.0"
  count                    = 1
  compartment_id           = var.compartment_ocid
  defined_tags             = {}
  freeform_tags            = local.freeform_tags
  vcn_cidrs                = ["10.0.0.0/16"]
  vcn_dns_label            = "nrstreaming"
  vcn_name                 = local.vcn_name
  lockdown_default_seclist = false
  subnets = {
    public = {
      cidr_block = "10.0.0.0/16"
      type       = "public"
      name       = local.subnet
    }
  }
  create_nat_gateway           = true
  nat_gateway_display_name     = local.nat_gateway
  create_service_gateway       = true
  service_gateway_display_name = local.service_gateway
  create_internet_gateway      = true # Enable creation of Internet Gateway
  internet_gateway_display_name = "NRInternetGateway" # Name the Internet Gateway
}

data "oci_core_route_tables" "default_vcn_route_table" {
  depends_on     = [module.vcn] # Ensure VCN is created before attempting to find its route tables
  compartment_id = var.compartment_ocid
  vcn_id         = module.vcn[0].vcn_id # Get the VCN ID from the module output

  filter {
    name   = "display_name"
    values = ["Default Route Table for ${local.vcn_name}"]
    regex  = false
  }
}

# Resource to manage the VCN's default route table and add your rule.
resource "oci_core_default_route_table" "default_internet_route" {
  manage_default_resource_id = data.oci_core_route_tables.default_vcn_route_table.route_tables[0].id
  depends_on = [
    module.vcn,
    data.oci_core_route_tables.default_vcn_route_table # Ensure the data source has run
  ]
  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = module.vcn[0].internet_gateway_id # Reference the internet gateway created by the module
    description       = "Route to Internet Gateway for New Relic metrics"
  }

}
