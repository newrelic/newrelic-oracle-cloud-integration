locals {
  home_region = [
    for rs in data.oci_identity_region_subscriptions.subscriptions.region_subscriptions :
    rs.region_name if rs.region_key == data.oci_identity_tenancy.current_tenancy.home_region_key
  ][0]

  freeform_tags = {
    newrelic-terraform = "true"
  }

  # Names for the network infra
  vcn_name        = "newrelic" + "-${var.nr_prefix}" + "-${var.region}" + "-metrics-vcn"
  nat_gateway     = "${local.vcn_name}-natgateway"
  service_gateway = "${local.vcn_name}-servicegateway"
  subnet          = "${local.vcn_name}-private-subnet"

  connector_hubs_map = jsondecode(data.external.connector_hubs.result.terraform_map)

  connector_hubs_data = [
    for key, value_str in local.connector_hubs_map : jsondecode(value_str)
  ]

  ingest_api_secret_ocid = data.external.connector_hubs.result.ingest_key_ocid
  user_api_secret_ocid   = data.external.connector_hubs.result.user_key_ocid
  compartment_ocid      = data.external.connector_hubs.result.compartment_id
  providerAccountId     = data.external.connector_hubs.result.provider_account_id
  user_api_key          = base64decode(data.oci_secrets_secretbundle.user_api_key.secret_bundle_content[0].content)
  stack_id              = data.oci_resourcemanager_stacks.current_stack.stacks[0].id
  newrelic_graphql_endpoint = {
    newrelic-staging-metric-api        = "https://staging-api.newrelic.com/graphql"
    newrelic-staging-vortex-metric-api = "https://staging-api.newrelic.com/graphql"
    newrelic-metric-api    = "https://api.newrelic.com/graphql"
    newrelic-eu-metric-api = "https://api.eu.newrelic.com/graphql"
  }[var.newrelic_endpoint]
  updateLinkAccount_graphql_query = <<EOF
mutation {
  cloudUpdateAccount(
    accountId: ${var.newrelic_account_id}
    accounts = {
      oci = {
        compartmentOcid: "${local.compartment_ocid}"
        linkedAccountId: "${local.providerAccountId}"
        metricStackOcid: "${local.stack_id}"
        ociHomeRegion: "${local.home_region}"
        tenantId: "${var.tenancy_ocid}"
        ociRegion: "${var.region}"
        userVaultOcid: "${local.ingest_api_secret_ocid}"
        ingestVaultOcid: "${local.user_api_secret_ocid}"
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
