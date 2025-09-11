locals {
  home_region = [
    for rs in data.oci_identity_region_subscriptions.subscriptions.region_subscriptions :
    rs.region_name if rs.region_key == data.oci_identity_tenancy.current_tenancy.home_region_key
  ][0]

  freeform_tags = {
    newrelic-terraform = "true"
  }

  # Names for the network infra
  vcn_name        = "${var.nr_prefix}-metrics-vcn"
  nat_gateway     = "${local.vcn_name}-natgateway"
  service_gateway = "${local.vcn_name}-servicegateway"
  subnet          = "${local.vcn_name}-private-subnet"

  connector_hubs_map = jsondecode(data.external.connector_hubs.result.terraform_map)

  connector_hubs_data = [
    for key, value_str in local.connector_hubs_map : jsondecode(value_str)
  ]

  ingest_api_secret_ocid = data.external.connector_hubs.result.ingest_key_ocid
  user_api_secret_ocid   = data.external.connector_hubs.result.user_key_ocid
  compartment_ocid      = data.external.connector_hubs.result.compartment_id

}
