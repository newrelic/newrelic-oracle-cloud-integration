# --- Home Provider Configurations ---
provider "oci" {
  alias        = "home_provider"
  tenancy_ocid = var.tenancy_ocid
  region       = local.home_region
}
