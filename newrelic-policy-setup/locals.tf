locals {
  home_region = [
    for region in data.oci_identity_region_subscriptions.subscriptions.region_subscriptions : region.region_name
    if region.is_home_region
  ][0]
  is_home_region = var.region == local.home_region

  freeform_tags = {
    newrelic-orm-terraform = "true"
  }
  newRelic_Metrics_Access_Policy   = contains(split(",", var.policy_stack), "METRICS")
  newRelic_Logs_Access_Policy      = contains(split(",", var.policy_stack), "LOGS")
  newRelic_Core_Integration_Policy = contains(split(",", var.policy_stack), "COMMON")
  newRelic_Cost_Access_Policy      = contains(split(",", var.policy_stack), "COST")
  newrelic_logs_policy             = "newrelic_logs_policy_ORM_DO_NOT_REMOVE_${local.random_id}"
  newrelic_metrics_policy          = "newrelic_metrics_policy_ORM_DO_NOT_REMOVE_${local.random_id}"
  newrelic_common_policy           = "newrelic_common_policy_ORM_DO_NOT_REMOVE_${local.random_id}"
  newrelic_cost_policy             = "newrelic_cost_policy_ORM_DO_NOT_REMOVE_${local.random_id}"
  dynamic_group_name               = "newrelic_dynamic_group_ORM_DO_NOT_REMOVE_${local.random_id}"
  instrumentation_type             = join(",", compact([
    local.newRelic_Metrics_Access_Policy ? "METRICS" : "",
    local.newRelic_Logs_Access_Policy    ? "LOGS"    : "",
    local.newRelic_Cost_Access_Policy    ? "COST"    : "",
  ]))
  linked_account_id                = var.linked_account_id != null ? var.linked_account_id : ""
  random_id                        = substr(md5(timestamp()), 0, 4)
  user_api_key = var.create_vault ? var.newrelic_user_api_key : (
    var.user_key_secret_ocid != "" ? base64decode(data.oci_secrets_secretbundle.user_api_key[0].secret_bundle_content[0].content) : var.newrelic_user_api_key
  )
  # Vault/compartment OCIDs for the update mutation — only populated when COMMON is present.
  # The guard for [0].id MUST match the resource's count condition exactly, otherwise
  # Terraform evaluates the reference at plan time when count=0 and fails.
  # - vault secrets:  count = newRelic_Core_Integration_Policy && create_vault ? 1 : 0
  # - compartment:    count = newRelic_Core_Integration_Policy ? 1 : 0
  # When COMMON absent → empty string; beyond-api-v2 getValueOrDefault falls back to
  # existing auth_label values — no overwrite.
  update_ingest_vault_ocid  = local.newRelic_Core_Integration_Policy && var.create_vault ? oci_vault_secret.ingest_api_key[0].id : (local.newRelic_Core_Integration_Policy ? var.ingest_key_secret_ocid : "")
  update_user_vault_ocid    = local.newRelic_Core_Integration_Policy && var.create_vault ? oci_vault_secret.user_api_key[0].id : (local.newRelic_Core_Integration_Policy ? var.user_key_secret_ocid : "")
  update_compartment_ocid   = local.newRelic_Core_Integration_Policy ? oci_identity_compartment.newrelic_compartment[0].id : ""

  updateLinkAccount_graphql_query  = <<EOF
mutation {
  cloudUpdateAccount(
    accountId: ${var.newrelic_account_id}
    accounts: {
      oci: {
        linkedAccountId: ${local.linked_account_id}
        ociRegion: "${var.region}"
        instrumentationType: "${local.instrumentation_type}"
        ${local.newRelic_Core_Integration_Policy ? "ingestVaultOcid: \"${local.update_ingest_vault_ocid}\"" : ""}
        ${local.newRelic_Core_Integration_Policy ? "userVaultOcid: \"${local.update_user_vault_ocid}\"" : ""}
        ${local.newRelic_Core_Integration_Policy ? "compartmentOcid: \"${local.update_compartment_ocid}\"" : ""}
      }
  }
) {
    linkedAccounts {
      id
      authLabel
      createdAt
      disabled
      externalId
      metricCollectionMode
      name
      nrAccountId
      updatedAt
    }
  }
}
EOF
  newrelic_graphql_endpoint = {
    US = "https://api.newrelic.com/graphql"
    EU = "https://api.eu.newrelic.com/graphql"
    JP = "https://api.jp.newrelic.com/graphql"
  }[var.newrelic_endpoint]
  linkAccount_graphql_query = <<EOF
mutation {
  cloudLinkAccount(
    accountId: ${var.newrelic_account_id}
    accounts: {
      oci: {
        name: "${var.link_account_name}"
        compartmentOcid: "${local.newRelic_Core_Integration_Policy ? oci_identity_compartment.newrelic_compartment[0].id : ""}"
        ociHomeRegion: "${local.home_region}"
        tenantId: "${var.tenancy_ocid}"
        ingestVaultOcid: "${local.newRelic_Core_Integration_Policy && var.create_vault ? oci_vault_secret.ingest_api_key[0].id : var.ingest_key_secret_ocid}"
        userVaultOcid: "${local.newRelic_Core_Integration_Policy && var.create_vault ? oci_vault_secret.user_api_key[0].id : var.user_key_secret_ocid}"
        ociClientId: "${var.client_id}"
        ociClientSecret: "${var.client_secret}"
        ociDomainUrl: "${var.oci_domain_url}"
        instrumentationType: "${local.instrumentation_type}"
        trustType: ${var.trust_type}
      }
    }
  ) {
    errors {
      linkedAccountId
      providerSlug
      message
      nrAccountId
      type
    }
    linkedAccounts {
      id
      authLabel
      createdAt
      disabled
      externalId
      metricCollectionMode
      name
      nrAccountId
      updatedAt
    }
  }
}
EOF
}
