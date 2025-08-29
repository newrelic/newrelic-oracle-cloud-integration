terraform {
  required_version = ">= 1.2.0"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "5.46.0"
    }
  }
}

#Key Vault and Secret for New Relic Ingest and User API Key
resource "oci_kms_vault" "newrelic_vault" {
  count = local.nr_common_stack ? 1 : 0
  compartment_id = var.compartment_ocid
  display_name   = "newrelic-vault"
  vault_type     = "DEFAULT"
  freeform_tags  = local.freeform_tags
}

resource "oci_kms_key" "newrelic_key" {
  count = local.nr_common_stack ? 1 : 0
  compartment_id = var.compartment_ocid
  display_name   = "newrelic-key"
  key_shape {
    algorithm = "AES"
    length    = 32
  }
  management_endpoint = oci_kms_vault.newrelic_vault[count.index].management_endpoint
  freeform_tags       = local.freeform_tags
}

resource "oci_vault_secret" "ingest_api_key" {
  count = local.nr_common_stack ? 1 : 0
  compartment_id = var.compartment_ocid
  vault_id       = oci_kms_vault.newrelic_vault[count.index].id
  key_id         = oci_kms_key.newrelic_key[count.index].id
  secret_name    = "NewRelicIngestAPIKey"
  secret_content {
    content_type = "BASE64"
    content      = base64encode(var.newrelic_ingest_api_key)
  }
  freeform_tags = local.freeform_tags
}

resource "oci_vault_secret" "user_api_key" {
  count = local.nr_common_stack ? 1 : 0
  compartment_id = var.compartment_ocid
  vault_id       = oci_kms_vault.newrelic_vault[count.index].id
  key_id         = oci_kms_key.newrelic_key[count.index].id
  secret_name    = "NewRelicUserAPIKey"
  secret_content {
    content_type = "BASE64"
    content      = base64encode(var.newrelic_user_api_key)
  }
  freeform_tags = local.freeform_tags
}

#Resource for the dynamic group
resource "oci_identity_dynamic_group" "nr_service_connector_group" {
  count          = local.is_home_region && local.nr_common_stack ? 1 : 0
  compartment_id = var.tenancy_ocid
  description    = "[DO NOT REMOVE] Dynamic group for service connector"
  matching_rule  = "ANY {resource.type = 'serviceconnector', resource.type = 'fnfunc'}"
  name           = local.dynamic_group_name
  defined_tags   = {}
  freeform_tags  = local.freeform_tags
}

#Resource for the metrics policy
resource "oci_identity_policy" "nr_metrics_policy" {
  count          = local.is_home_region && local.nr_metrics_stack ? 1 : 0
  depends_on     = [oci_identity_dynamic_group.nr_service_connector_group]
  compartment_id = var.tenancy_ocid
  description    = "[DO NOT REMOVE] Policy to have read metrics for newrelic integration"
  name           = local.newrelic_metrics_policy
  statements     = [
    "Allow dynamic-group ${local.dynamic_group_name} to read metrics in tenancy"
  ]
  defined_tags  = {}
  freeform_tags = local.freeform_tags
}

#Resource for the logging policy
resource "oci_identity_policy" "nr_logs_policy" {
  count          = local.nr_logging_stack ? 1 : 0
  depends_on     = [oci_identity_dynamic_group.nr_service_connector_group]
  compartment_id = var.tenancy_ocid
  description    = "[DO NOT REMOVE] Policy to have read logs for newrelic integration"
  name           = local.newrelic_metrics_policy
  statements     = [
    "Allow dynamic-group ${local.dynamic_group_name} to read log-content in tenancy"
  ]
  defined_tags  = {}
  freeform_tags = local.freeform_tags
}

#Resource for the metrics/Logging (Common) policies
resource "oci_identity_policy" "nr_common_policy" {
  count          = local.is_home_region && local.nr_common_stack ? 1 : 0
  depends_on     = [oci_identity_dynamic_group.nr_service_connector_group]
  compartment_id = var.tenancy_ocid
  description    = "[DO NOT REMOVE] Policy to have any connector hub read from monitoring source and write to a target function"
  name           = local.newrelic_common_policy
  statements     = [
    "Allow dynamic-group ${local.dynamic_group_name} to use fn-function in tenancy",
    "Allow dynamic-group ${local.dynamic_group_name} to use fn-invocation in tenancy",
    "Allow dynamic-group ${local.dynamic_group_name} to read secret-bundles in tenancy",
  ]
  defined_tags  = {}
  freeform_tags = local.freeform_tags
}

# Resource to link the New Relic account and configure the integration
resource "null_resource" "newrelic_link_account" {
  count = local.nr_common_stack ? 1 : 0
  depends_on = [oci_vault_secret.user_api_key,oci_vault_secret.ingest_api_key, oci_identity_policy.nr_metrics_policy, oci_identity_dynamic_group.nr_service_connector_group]
  provisioner "local-exec" {
    command = <<EOT
      # Main execution for cloudLinkAccount
      response=$(curl --silent --request POST \
        --url "${local.newrelic_graphql_endpoint}" \
        --header "API-Key: ${var.newrelic_user_api_key}" \
        --header "Content-Type: application/json" \
        --header "User-Agent: insomnia/11.1.0" \
        --data '${jsonencode({
          query = local.linkAccount_graphql_query
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
