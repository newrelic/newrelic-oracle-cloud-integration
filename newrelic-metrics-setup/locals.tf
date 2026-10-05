locals {
  home_region = [
    for rs in data.oci_identity_region_subscriptions.subscriptions.region_subscriptions :
    rs.region_name if rs.region_key == data.oci_identity_tenancy.current_tenancy.home_region_key
  ][0]

  freeform_tags = {
    newrelic-orm-terraform = "true"
  }

  # Names for the network infra
  vcn_name        = "newrelic-${var.nr_prefix}-${var.region}-metrics-vcn"
  nat_gateway     = "${local.vcn_name}-natgateway"
  service_gateway = "${local.vcn_name}-servicegateway"
  subnet          = "${local.vcn_name}-private-subnet"

  connector_hubs_map = jsondecode(data.external.connector_hubs.result.terraform_map)

  connector_hubs_data = [
    for key, value_str in local.connector_hubs_map : jsondecode(value_str)
  ]

  ingest_api_secret_ocid = data.external.connector_hubs.result.ingest_key_ocid
  user_api_secret_ocid   = data.external.connector_hubs.result.user_key_ocid
  compartment_ocid       = data.external.connector_hubs.result.compartment_id
  providerAccountId      = data.external.connector_hubs.result.provider_account_id
  user_api_key           = base64decode(data.oci_secrets_secretbundle.user_api_key.secret_bundle_content[0].content)
  stack_id               = data.oci_resourcemanager_stacks.current_stack.stacks[0].id

  # The function runs from a copy of var.function_image in the tenancy's own Container Registry.
  ocir_host                 = "${var.region}.ocir.io"
  ocir_namespace            = oci_artifacts_container_repository.metrics_function_repo.namespace
  function_image_repository = "newrelic-${lower(var.nr_prefix)}/oci-metrics-forwarder"
  function_image_digest     = data.external.function_image.result.digest
  function_image            = "${local.ocir_host}/${local.ocir_namespace}/${local.function_image_repository}:${data.external.function_image.result.tag}"
  create_registry_token     = nonsensitive(var.registry_auth_token == "")
  registry_username         = "${local.ocir_namespace}/${var.registry_username != "" ? var.registry_username : data.oci_identity_user.registry_user[0].name}"
  # Unmarked so Terraform keeps showing the copy's log output; image_mirror.py never prints it.
  registry_password = local.create_registry_token ? oci_identity_auth_token.registry_push[0].token : nonsensitive(var.registry_auth_token)
  newrelic_graphql_endpoint = {
    US = "https://api.newrelic.com/graphql"
    EU = "https://api.eu.newrelic.com/graphql"
    JP = "https://api.jp.newrelic.com/graphql"
  }[var.newrelic_endpoint]
  updateLinkAccount_graphql_query = <<EOF
mutation {
  cloudUpdateAccount(
    accountId: ${var.newrelic_account_id}
    accounts: {
      oci: {
        compartmentOcid: "${local.compartment_ocid}"
        linkedAccountId: ${local.providerAccountId}
        metricStackOcid: "${local.stack_id}"
        ociRegion: "${var.region}"
        userVaultOcid: "${local.user_api_secret_ocid}"
        ingestVaultOcid: "${local.ingest_api_secret_ocid}"
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
}
