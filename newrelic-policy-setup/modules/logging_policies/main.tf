terraform {
  required_version = ">= 1.2.0"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "5.46.0"
    }
  }
}

provider "oci" {
  tenancy_ocid = var.tenancy_ocid
  region       = var.region
}

# Cross-Tenancy New Relic Read-Only Access Policy
resource "oci_identity_policy" "cross_tenancy_read_only_policy" {
  compartment_id = var.compartment_ocid
  name           = "New_Relic_Cross_Tenancy_Read_Only_Policy"
  description    = "Policy granting New Relic tenancy read-only access to connector hubs, VCNs, and log groups."
  statements     = [
    "Define tenancy NRTenancyAlias as ${var.new_relic_tenancy_ocid}",
    "Define group NRCustomerOCIAccessGroupAlias as ${var.new_relic_group_ocid}",
    "Admit group NRCustomerOCIAccessGroupAlias of tenancy NRTenancyAlias to read log-content in tenancy",
    "Admit group NRCustomerOCIAccessGroupAlias of tenancy NRTenancyAlias to inspect compartments in tenancy"
  ]
}

# Policies for Connector Hubs in given Compartment
resource "oci_identity_dynamic_group" "connector_hub_dg" {
  compartment_id = var.tenancy_ocid
  name           = "New_Relic_Service_Connector_Hubs_DG"
  description    = "Dynamic group for all Service Connector Hubs in the specified compartment."
  matching_rule  = "ALL {resource.type = 'serviceconnector', instance.compartment.id = '${var.compartment_ocid}'}"
}

resource "oci_identity_policy" "connector_hub_policy" {
  compartment_id = var.compartment_ocid
  name           = "New_Relic_Connector_Hub_Log_Access"
  description    = "Allows connector hubs to read logs and trigger functions."
  statements     = [
    "Allow dynamic-group ${oci_identity_dynamic_group.connector_hub_dg.name} to read log-content in tenancy",
    "Allow dynamic-group ${oci_identity_dynamic_group.connector_hub_dg.name} to use fn-function in compartment id ${var.compartment_ocid}",
  ]
}

# Cross-Regional Vault Access for Functions
resource "oci_identity_dynamic_group" "all_functions_dg" {
  compartment_id = var.tenancy_ocid
  name           = "New_Relic_All_Functions_DG"
  description    = "Dynamic group for all functions in the compartment."
  matching_rule  = "ALL {instance.compartment.id = '${var.compartment_ocid}'}"
}

resource "oci_identity_policy" "functions_vault_access_policy" {
  compartment_id = var.compartment_ocid
  name           = "New_Relic_Functions_Vault_Access_Policy"
  description    = "Policy allowing functions to read secrets from the vault."
  statements     = [
    "Allow dynamic-group ${oci_identity_dynamic_group.all_functions_dg.name} to read secret-bundles in compartment id ${var.compartment_ocid}",
  ]
}