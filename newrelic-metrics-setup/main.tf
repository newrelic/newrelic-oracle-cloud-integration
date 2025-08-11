terraform {
  required_version = ">= 1.2.0"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "5.46.0"
    }
    external = {
      source  = "hashicorp/external"
      version = "2.3.5"
    }
  }
}

provider "oci" {
  alias        = "home"
  tenancy_ocid = var.tenancy_ocid
  region       = var.region
}

resource "oci_functions_application" "metrics_function_app" {
  compartment_id = var.compartment_ocid
  config = {
    "FORWARD_TO_NR"                = "True"
    "LOGGING_ENABLED"              = "False"
    "NR_METRIC_ENDPOINT"           = var.newrelic_endpoint
    "TENANCY_OCID"                 = var.compartment_ocid
    "SECRET_OCID"                  = var.home_secret_ocid
    "VAULT_REGION"                 = local.home_region
  }
  defined_tags               = {}
  display_name               = "${var.nr_prefix}-metrics-function-app"
  freeform_tags              = local.freeform_tags
  network_security_group_ids = []
  shape                      = "GENERIC_X86"
  subnet_ids = [
    data.oci_core_subnet.input_subnet.id,
  ]
}

resource "oci_functions_function" "metrics_function" {
  application_id = oci_functions_application.metrics_function_app.id
  display_name   = "${oci_functions_application.metrics_function_app.display_name}-metrics-function"
  memory_in_mbs  = "256"
  defined_tags   = {}
  freeform_tags = local.freeform_tags
  image          = "${var.region}.ocir.io/idms1yfytybe/public-newrelic-repo:latest"
}

resource "oci_sch_service_connector" "nr_service_connector" {
  depends_on     = [oci_functions_function.metrics_function]
  compartment_id = var.compartment_ocid
  display_name   = "${var.nr_prefix}-connector-hub"

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
    batch_size_in_kbs = 100
    batch_time_in_sec = 60
    compartment_id    = var.compartment_ocid
    function_id       = oci_functions_function.metrics_function.id
  }

  # Optional tags and additional metadata
  description   = "[DO NOT DELETE] - Service Connector from Monitoring to Streaming"
  defined_tags  = {}
  freeform_tags = {}
}


module "vcn" {
  source                   = "oracle-terraform-modules/vcn/oci"
  version                  = "3.6.0"
  count                    = var.create_vcn ? 1 : 0
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
  count = var.create_vcn ? 1 : 0
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
  manage_default_resource_id = data.oci_core_route_tables.default_vcn_route_table[0].route_tables[0].id
  count = var.create_vcn ? 1 : 0
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

output "vcn_network_details" {
  depends_on  = [module.vcn]
  description = "Output of the created network infra"
  value = var.create_vcn && length(module.vcn) > 0 ? {
    vcn_id             = module.vcn[0].vcn_id
    nat_gateway_id     = module.vcn[0].nat_gateway_id
    nat_route_id       = module.vcn[0].nat_route_id
    service_gateway_id = module.vcn[0].service_gateway_id
    sgw_route_id       = module.vcn[0].sgw_route_id
    subnet_id          = module.vcn[0].subnet_id[local.subnet]
  } : {
    vcn_id             = ""
    nat_gateway_id     = ""
    nat_route_id       = ""
    service_gateway_id = ""
    sgw_route_id       = ""
    subnet_id          = var.function_subnet_id
  }
}

output "stack_id" {
  value = data.oci_resourcemanager_stacks.test_stack.stacks[0].id
}
