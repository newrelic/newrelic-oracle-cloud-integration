locals {
  home_region = [
    for region in data.oci_identity_region_subscriptions.subscriptions.region_subscriptions : region.region_name
    if region.is_home_region
  ][0]
  is_home_region = var.region == local.home_region

  freeform_tags = {
    newrelic-terraform = "true"
  }
  policy_stack_chars = split("", var.policy_stack)
  newRelic_Metrics_Access_Policy = local.policy_stack_chars[0] == "Y"
  newRelic_Logs_Access_Policy = local.policy_stack_chars[1] == "Y"
  newRelic_Core_Integration_Policy = local.policy_stack_chars[2] == "Y"
  newrelic_logs_policy     = "newrelic-logs-policy"
  newrelic_metrics_policy = "newrelic-metrics-policy"
  newrelic_common_policy  = "newrelic-common-policy"
  dynamic_group_name      = "newrelic-dynamic-group"
  newrelic_graphql_endpoint = "https://api.newrelic.com/graphql"
  linkAccount_graphql_query = <<EOF
   mutation {
    cloudLinkAccount(
    accountId: ${var.newrelic_account_id},
    accounts: {oci: {name: "nr_oci", tenantId: "${var.tenancy_ocid}", ingestKeyOcid: "${oci_vault_secret.ingest_api_key[0].id}", userKeyOcid: "${oci_vault_secret.user_api_key[0].id}", clientId: "${var.client_id}", clientSecret: "${var.client_secret}", ociDomainUrl: "${var.oci_domain_url}", svcUserName: "${var.svc_user_name}"}}
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
