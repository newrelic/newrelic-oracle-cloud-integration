locals {
  home_region = [
    for region in data.oci_identity_region_subscriptions.subscriptions.region_subscriptions : region.region_name
    if region.is_home_region
  ][0]
  is_home_region = var.region == local.home_region

  freeform_tags = {
    newrelic-terraform = "true"
  }
  newRelic_Metrics_Access_Policy = contains(split(",", var.policy_stack), "METRICS")
  newRelic_Logs_Access_Policy    = contains(split(",", var.policy_stack), "LOGS")
  newRelic_Core_Integration_Policy = contains(split(",", var.policy_stack), "COMMON")
  newrelic_logs_policy     = "newrelic-logs-policy"
  newrelic_metrics_policy = "newrelic-metrics-policy"
  newrelic_common_policy  = "newrelic-common-policy"
  dynamic_group_name      = "newrelic-dynamic-group"
  newrelic_graphql_endpoint = "https://api.newrelic.com/graphql"
  linkAccount_graphql_query = <<EOF
   mutation {
    cloudLinkAccount(
    accountId: ${var.newrelic_account_id},
    accounts = {
    oci = {
      name: "nr_oci",
      compartmentOcid: local.newRelic_Core_Integration_Policy ? oci_identity_compartment.newrelic_compartment[0].id : "",
      ociHomeRegion: local.home_region,
      tenantId: var.tenancy_ocid,
      ingestVaultOcid: local.newRelic_Core_Integration_Policy ? oci_vault_secret.ingest_api_key[0].id : "",
      userVaultOcid: local.newRelic_Core_Integration_Policy ? oci_vault_secret.user_api_key[0].id : "",
      ociClientId: var.client_id,
      ociClientSecret: var.client_secret,
      ociDomainUrl: var.oci_domain_url,
      ociSvcUserName: var.svc_user_name
    }
    }) {
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
