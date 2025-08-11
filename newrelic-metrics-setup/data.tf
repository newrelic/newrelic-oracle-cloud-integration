data "oci_identity_tenancy" "current_tenancy" {
  tenancy_id = var.tenancy_ocid
}

data "oci_identity_region_subscriptions" "subscriptions" {
  tenancy_id = var.tenancy_ocid
}

data "oci_core_subnet" "input_subnet" {
  depends_on = [module.vcn]
  #Required
  subnet_id = var.create_vcn ? module.vcn[0].subnet_id[local.subnet] : var.function_subnet_id
}

data "oci_resourcemanager_stacks" "test_stack" {
  compartment_id = var.compartment_ocid

  filter {
    name   = "display_name"
    values = [".*newrelic-metrics-setup.*"]
    regex  = true
  }
}
