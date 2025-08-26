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
  nr_metrics_stack = local.policy_stack_chars[0] == "Y"
  nr_logging_stack = local.policy_stack_chars[1] == "Y"
  nr_common_stack = local.policy_stack_chars[2] == "Y"
  newrelic_metrics_policy = "newrelic-metrics-policy"
  newrelic_common_policy  = "newrelic-common-policy"
  dynamic_group_name      = "newrelic-dynamic-group"
  newrelic_graphql_endpoint = "https://api.newrelic.com/graphql"
  linkAccount_graphql_query = <<EOF
   mutation {
    cloudLinkAccount(
    accountId: ${var.newrelic_account_id},
    accounts: {oci: {name: "nr_oci", tenantId: "${var.tenancy_ocid}"}}
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
