locals {
  home_region = [
    for region in data.oci_identity_region_subscriptions.subscriptions.region_subscriptions : region.region_name
    if region.is_home_region
  ][0]
  is_home_region = var.region == local.home_region

  freeform_tags = {
    newrelic-terraform = "true"
  }
  newRelic_Metrics_Access_Policy   = contains(split(",", var.policy_stack), "METRICS")
  newRelic_Logs_Access_Policy      = contains(split(",", var.policy_stack), "LOGS")
  newRelic_Core_Integration_Policy = contains(split(",", var.policy_stack), "COMMON")
  newrelic_logs_policy             = "newrelic_logs_policy_ORM_DO_NOT_REMOVE"
  newrelic_metrics_policy          = "newrelic_metrics_policy_ORM_DO_NOT_REMOVE"
  newrelic_common_policy           = "newrelic_common_policy_ORM_DO_NOT_REMOVE"
  dynamic_group_name               = "newrelic_dynamic_group_ORM_DO_NOT_REMOVE"
  instrumentation_type             = local.newRelic_Metrics_Access_Policy && local.newRelic_Logs_Access_Policy && local.newRelic_Core_Integration_Policy ? "METRICS,LOGS" : (local.newRelic_Logs_Access_Policy && local.newRelic_Core_Integration_Policy) || local.newRelic_Logs_Access_Policy ? "LOGS" : (local.newRelic_Metrics_Access_Policy && local.newRelic_Core_Integration_Policy) || local.newRelic_Metrics_Access_Policy ? "METRICS" : ""
  updateLinkAccount_graphql_query  = <<EOF
mutation {
  cloudUpdateAccount(
    accountId: ${var.newrelic_account_id}
    accounts: {
      oci: {
        linkedAccountId: ${var.linked_account_id}
        ociRegion: "${var.region}"
        instrumentationType: "${local.instrumentation_type}"
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
    newrelic-metric-api    = "https://api.newrelic.com/graphql"
    newrelic-eu-metric-api = "https://api.eu.newrelic.com/graphql"
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
        ingestVaultOcid: "${local.newRelic_Core_Integration_Policy ? oci_vault_secret.ingest_api_key[0].id : ""}"
        userVaultOcid: "${local.newRelic_Core_Integration_Policy ? oci_vault_secret.user_api_key[0].id : ""}"
        ociClientId: "${var.client_id}"
        ociClientSecret: "${var.client_secret}"
        ociDomainUrl: "${var.oci_domain_url}"
        ociSvcUserName: "${var.svc_user_name}"
        instrumentationType: "${local.instrumentation_type}"
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
