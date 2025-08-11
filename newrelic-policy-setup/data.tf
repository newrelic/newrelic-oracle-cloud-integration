data "oci_identity_user" "current_user" {
  user_id = var.current_user_ocid
}

data "oci_identity_region_subscriptions" "subscriptions" {
  tenancy_id = var.tenancy_ocid
}
