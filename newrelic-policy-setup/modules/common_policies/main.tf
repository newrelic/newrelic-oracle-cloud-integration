# ------ Common Resources -----

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
  alias        = "home"
  tenancy_ocid = var.tenancy_ocid
  user_ocid    = var.user_id
  region       = var.region
}


# Dynamic Group for Service Connector Hub and Function
resource "oci_identity_dynamic_group" "nr_service_connector_group" {
  compartment_id = var.tenancy_ocid
  description    = "[DO NOT REMOVE] Dynamic group for service connector"
  matching_rule  = "ANY {resource.type = 'serviceconnector', resource.type = 'fnfunc'}"
  name           = var.dynamic_group_name
  defined_tags   = {}
  freeform_tags  = var.freeform_tags
}

# Policies for Dynamic Group
resource "oci_identity_policy" "nr_common_policy" {
  compartment_id = var.tenancy_ocid
  description    = "[DO NOT REMOVE] Policy to have any connector hub read from monitoring source and write to a target function"
  name           = var.newrelic_common_policy
  statements     = [
    "Allow dynamic-group ${var.dynamic_group_name} to use fn-function in tenancy",
    "Allow dynamic-group ${var.dynamic_group_name} to use fn-invocation in tenancy",
    "Allow dynamic-group ${var.dynamic_group_name} to read secret-bundles in tenancy",
  ]
  defined_tags  = {}
  freeform_tags = var.freeform_tags
}

# Key Vault and Secret for New Relic Ingest API Key
resource "oci_kms_vault" "newrelic_vault" {
  compartment_id = var.compartment_ocid
  display_name   = "newrelic-vault"
  vault_type     = "DEFAULT"
  freeform_tags  = var.freeform_tags
}

resource "oci_kms_key" "newrelic_key" {
  compartment_id = var.compartment_ocid
  display_name   = "newrelic-key"
  key_shape {
    algorithm = "AES"
    length    = 32
  }
  management_endpoint = oci_kms_vault.newrelic_vault.management_endpoint
  freeform_tags       = var.freeform_tags
}

resource "oci_vault_secret" "ingest_api_key" {
  compartment_id = var.compartment_ocid
  vault_id       = oci_kms_vault.newrelic_vault.id
  key_id         = oci_kms_key.newrelic_key.id
  secret_name    = "NewRelicIngestAPIKey"
  secret_content {
    content_type = "BASE64"
    content      = base64encode(var.newrelic_ingest_api_key)
  }
  freeform_tags = var.freeform_tags
}

resource "oci_vault_secret" "user_api_key" {
  compartment_id = var.compartment_ocid
  vault_id       = oci_kms_vault.newrelic_vault.id
  key_id         = oci_kms_key.newrelic_key.id
  secret_name    = "NewRelicUserAPIKey"
  secret_content {
    content_type = "BASE64"
    content      = base64encode(var.newrelic_user_api_key)
  }
  freeform_tags = var.freeform_tags
}

# Link Account Resource
resource "null_resource" "newrelic_link_account" {
  provisioner "local-exec" {
    command = <<EOT
      # Main execution for cloudLinkAccount
      response=$(curl --silent --request POST \
        --url "${var.newrelic_graphql_endpoint}" \
        --header "API-Key: ${var.newrelic_user_api_key}" \
        --header "Content-Type: application/json" \
        --header "User-Agent: insomnia/11.1.0" \
        --data '${jsonencode({
          query = var.linkAccount_graphql_query
        })}')

      # Log the full response for debugging
      echo "Full Response: $response"

      # Extract errors from the response
      root_errors=$(echo "$response" | jq -r '.errors[]?.message // empty')
      account_errors=$(echo "$response" | jq -r '.data.cloudLinkAccount.errors[]?.message // empty')

      # Combine errors
      errors="$root_errors"$'\n'"$account_errors"

      # Check if errors exist
      if [ -n "$errors" ] && [ "$errors" != $'\n' ]; then
        echo "Operation failed with the following errors:" >&2
        echo "$errors" | while IFS= read -r error; do
          echo "- $error" >&2
        done
        exit 1
      fi

    EOT
  }
}