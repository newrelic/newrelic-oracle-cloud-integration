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

data "oci_resourcemanager_stacks" "current_stack" {
  compartment_id = var.compartment_ocid

  filter {
    name   = "display_name"
    values = [".*newrelic-metrics-setup.*"]
    regex  = true
  }
}

# The data source to execute the Python script
data "external" "connector_hubs" {
  program = ["python", "${path.module}/connector.py"]
  query = {
    "payload_link" = var.payload_link
  }
}

data "oci_secrets_secretbundle" "user_api_key" {
  secret_id = local.user_api_secret_ocid
  provider  = oci.home_provider
}

# Resolved on every plan, so re-applying the stack notices when the tag points at a new image.
data "external" "function_image" {
  program = ["python", "${path.module}/image_mirror.py", "resolve"]
  query = {
    source_image = var.function_image
    platform     = "linux/amd64"
  }
}

data "oci_identity_user" "registry_user" {
  count   = var.registry_username == "" ? 1 : 0
  user_id = var.current_user_ocid
}
