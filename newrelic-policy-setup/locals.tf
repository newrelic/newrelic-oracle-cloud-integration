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
  newrelic_account_id = 3631942
  tenancy_ocid = "ocid1.tenancy.oc1..aaaaaaaajwhwjzag7c5vze6hq5metiowjsjbojglfn5zamh3vn4xdq5i2ppq"
  newrelic_user_api_key = "NRAK-13R69O4RT5KLKYOVQ47S8REXJUE"
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
