locals {
  home_region = [
    for region in data.oci_identity_region_subscriptions.subscriptions.region_subscriptions : region.region_name
    if region.is_home_region
  ][0]
  is_home_region = var.region == local.home_region

  freeform_tags = {
    newrelic-terraform = "true"
  }

  newrelic_graphql_endpoint = "https://api.newrelic.com/graphql"
  newrelic_account_id = var.newrelic_account_id
  tenancy_ocid = var.tenancy_ocid
  newrelic_user_api_key = var.newrelic_ingest_api_key
  linkAccount_graphql_query = <<EOF
   mutation {
    cloudLinkAccount(
    accountId: ${local.newrelic_account_id}
    accounts: {oci: {name: "nr_oci", tenantId: "${local.tenancy_ocid}"}}
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
