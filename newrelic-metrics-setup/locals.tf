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
  subnet          = "${local.vcn_name}-public-subnet"

  # Iterate over the result map from the external data source.
  connector_hubs_data = [
    for key, value_str in data.external.connector_hubs.result : jsondecode(value_str)
  ]

}
