data "oci_identity_domains" "domain" {
  compartment_id = var.tenancy_ocid
  display_name   = var.identity_domain_name
}

data "oci_identity_compartment" "root" {
  id = var.tenancy_ocid
}

data "oci_identity_domains_app_roles" "app_roles" {
  idcs_endpoint   = local.identity_domain_url
  attributes      = "id,displayName"
  app_role_filter = "displayName eq \"Identity Domain Administrator\""
}
