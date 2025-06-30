terraform {
  required_version = ">= 1.2.0"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 5.46.0"
    }
  }
}

provider "oci" {
  alias        = "home_region"
  tenancy_ocid = var.tenancy_ocid
  user_ocid    = var.current_user_ocid
  region       = "ap-hyderabad-1"
}

provider "oci" {
  alias        = "secondary_region"
  tenancy_ocid = var.tenancy_ocid
  user_ocid    = var.current_user_ocid
  region       = "us-ashburn-1"
}

resource "oci_artifacts_container_repository" "public_repository_us_ashburn_1" {
  count          = contains(var.selectedRegion, "us-ashburn-1") ? 1 : 0
  compartment_id = var.compartment_ocid
  display_name   = "public-newrelic-repo"
  is_public      = true

  freeform_tags = {
    created_by = "terraform"
  }

  provider = oci.secondary_region
}

resource "oci_artifacts_container_repository" "public_repository_ap_hyderabad_1" {
  count          = contains(var.selectedRegion, "ap-hyderabad-1") ? 1 : 0
  compartment_id = var.compartment_ocid
  display_name   = "public-newrelic-repo"
  is_public      = true

  freeform_tags = {
    created_by = "terraform"
  }

  provider = oci.home_region
}
