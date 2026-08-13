# IAM Group for service user (UPST only)
resource "oci_identity_domains_group" "newrelic_service_group" {
  count = local.is_upst ? 1 : 0

  idcs_endpoint  = local.identity_domain_url
  schemas        = ["urn:ietf:params:scim:schemas:core:2.0:Group"]
  display_name   = "${local.resource_prefix}-svc-user-group-${local.suffix}"
  attribute_sets = ["all"]

  lifecycle {
    ignore_changes = [schemas]
  }
}

# Service user (UPST only)
resource "oci_identity_domains_user" "svc_user" {
  count = local.is_upst ? 1 : 0

  idcs_endpoint = local.identity_domain_url
  schemas       = ["urn:ietf:params:scim:schemas:core:2.0:User"]
  user_name     = "${local.resource_prefix}-wif-svc-user-${local.suffix}-${local.random_id}"

  urnietfparamsscimschemasoracleidcsextensionuser_user {
    service_user = true
  }

  lifecycle {
    ignore_changes = [schemas]
  }
}

# Add service user to group (UPST only)
resource "oci_identity_user_group_membership" "svc_user_group_membership" {
  count    = local.is_upst ? 1 : 0
  group_id = oci_identity_domains_group.newrelic_service_group[0].ocid
  user_id  = oci_identity_domains_user.svc_user[0].ocid
}

# IAM policy — always at tenancy root since it grants read access across the tenancy
# UPST: group-based; RPST: claim-based on ext_account_id + ext_tenancy_id
resource "oci_identity_policy" "newrelic_service_policy" {
  compartment_id = var.tenancy_ocid
  name           = "${local.resource_prefix}-svc-user-policy-${local.suffix}"
  description    = "[DO NOT REMOVE] Policy granting New Relic read-only access to OCI resources"

  statements = local.is_upst ? [
    "Allow group '${oci_identity_domains_group.newrelic_service_group[0].display_name}' to read all-resources in tenancy",
    ] : [
    format(
      "allow any-user to read all-resources in tenancy where all { request.principal.type = 'identityfederateddomainapp', request.principal.ext_account_id = '%s', request.principal.ext_tenancy_id = '%s' }",
      var.newrelic_account_id,
      var.tenancy_ocid
    ),
  ]

  depends_on = [oci_identity_domains_group.newrelic_service_group]
}

# Admin app — elevated temporary app used only to create the Identity Propagation Trust
resource "oci_identity_domains_app" "admin_app" {
  idcs_endpoint   = local.identity_domain_url
  schemas         = ["urn:ietf:params:scim:schemas:oracle:idcs:App"]
  display_name    = "${local.resource_prefix}-ida-app-${local.suffix}"
  active          = var.activate_oauth_apps
  allowed_grants  = ["client_credentials"]
  is_oauth_client = true
  client_type     = "confidential"
  bypass_consent  = true
  attribute_sets  = ["all"]

  based_on_template {
    value = "CustomWebAppTemplateId"
  }

  # OCI requires apps to be deactivated before they can be deleted.
  # This provisioner runs before Terraform sends the DELETE request.
  provisioner "local-exec" {
    when    = destroy
    command = <<EOT
      oci --no-retry --endpoint "${self.idcs_endpoint}" identity-domains app patch \
        --app-id "${self.id}" \
        --schemas '["urn:ietf:params:scim:api:messages:2.0:PatchOp"]' \
        --operations '[{"op":"replace","path":"active","value":false}]' \
        2>&1 || true
      sleep 5
    EOT
  }

  lifecycle {
    ignore_changes = [schemas]
  }
}

# Token exchange app — runtime OAuth client New Relic uses for WIF token exchange
resource "oci_identity_domains_app" "token_exchange_app" {
  idcs_endpoint   = local.identity_domain_url
  schemas         = ["urn:ietf:params:scim:schemas:oracle:idcs:App"]
  display_name    = "${local.resource_prefix}-token-exchange-app-${local.suffix}"
  active          = var.activate_oauth_apps
  allowed_grants  = ["client_credentials"]
  is_oauth_client = true
  client_type     = "confidential"
  bypass_consent  = true
  attribute_sets  = ["all"]

  based_on_template {
    value = "CustomWebAppTemplateId"
  }

  # OCI requires apps to be deactivated before they can be deleted.
  # This provisioner runs before Terraform sends the DELETE request.
  provisioner "local-exec" {
    when    = destroy
    command = <<EOT
      oci --no-retry --endpoint "${self.idcs_endpoint}" identity-domains app patch \
        --app-id "${self.id}" \
        --schemas '["urn:ietf:params:scim:api:messages:2.0:PatchOp"]' \
        --operations '[{"op":"replace","path":"active","value":false}]' \
        2>&1 || true
      sleep 5
    EOT
  }

  lifecycle {
    ignore_changes = [schemas]
  }
}

# Grant Identity Domain Administrator role to admin app
resource "oci_identity_domains_grant" "admin_app_domain_admin_grant" {
  idcs_endpoint   = local.identity_domain_url
  schemas         = ["urn:ietf:params:scim:schemas:oracle:idcs:Grant"]
  grant_mechanism = "ADMINISTRATOR_TO_APP"
  attribute_sets  = ["all"]

  grantee {
    value = oci_identity_domains_app.admin_app.id
    type  = "App"
  }

  entitlement {
    attribute_name  = "appRoles"
    attribute_value = data.oci_identity_domains_app_roles.app_roles.app_roles[0].id
  }

  app {
    value = "IDCSAppId"
  }
}

locals {
  # trust_body_upst references svc_user[0].id. Guard with try() so Terraform doesn't
  # error when trust_type = RPST and svc_user count = 0. local.trust_body then selects
  # only the branch that matches trust_type, so the guarded value is never actually used.
  svc_user_id = try(oci_identity_domains_user.svc_user[0].id, "")

  trust_body_upst = jsonencode({
    active            = true
    allowImpersonation = true
    issuer            = local.newrelic_config.issuer_name
    name              = var.trust_name
    oauthClients      = [oci_identity_domains_app.token_exchange_app.name]
    publicKeyEndpoint = local.newrelic_config.public_jwks_url
    impersonationServiceUsers = [{
      rule  = "sub eq '${local.newrelic_config.subject_name}'"
      value = local.svc_user_id
    }]
    subjectType = "User"
    type        = "JWT"
    schemas     = ["urn:ietf:params:scim:schemas:oracle:idcs:IdentityPropagationTrust"]
  })

  trust_body_rpst = jsonencode({
    active                = true
    allowImpersonation    = true
    issuer                = local.newrelic_config.rpst_issuer_name
    name                  = "${var.trust_name}-rpst"
    oauthClients          = [oci_identity_domains_app.token_exchange_app.name]
    publicKeyEndpoint     = local.newrelic_config.public_jwks_url
    impersonatingResource = local.impersonating_resource
    claimPropagations     = ["ext_account_id", "ext_tenancy_id", "ext_resource_tag"]
    subjectType           = "Resource"
    type                  = "JWT"
    schemas               = ["urn:ietf:params:scim:schemas:oracle:idcs:IdentityPropagationTrust"]
  })

  trust_body = local.is_upst ? local.trust_body_upst : local.trust_body_rpst
}

# Fetch IDA OAuth token and create the Identity Propagation Trust in one step.
# client_secret is stored in triggers because OCI never returns it in GET responses —
# ORM's post-apply refresh overwrites oci_identity_domains_app.token_exchange_app.client_secret
# with "". Triggers are user-owned state and are never refreshed from the provider.
# We store it here (not in a separate null_resource) because this resource runs after
# admin_app_domain_admin_grant, by which time client_secret is confirmed available.
resource "null_resource" "trust_setup" {
  triggers = {
    client_secret = oci_identity_domains_app.token_exchange_app.client_secret
  }
  provisioner "local-exec" {
    command = <<EOT
      sleep 20
      OAUTH_TOKEN=$(printf '%s:%s' '${oci_identity_domains_app.admin_app.name}' '${oci_identity_domains_app.admin_app.client_secret}' | base64 | tr -d '\n')
      TOKEN_RESPONSE=$(curl --silent --location '${local.identity_domain_url}/oauth2/v1/token' \
        --header 'Content-Type: application/x-www-form-urlencoded;charset=UTF-8' \
        --header "Authorization: Basic $OAUTH_TOKEN" \
        --data 'grant_type=client_credentials&scope=urn:opc:idm:__myscopes__')

      ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token // empty')
      if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" = "null" ]; then
        echo "Token fetch failed: $(echo "$TOKEN_RESPONSE" | jq -r '.error_description // .error // "Unknown"')" >&2
        exit 1
      fi

      sleep 10
      TRUST_RESPONSE=$(curl --silent --location '${local.identity_domain_url}/admin/v1/IdentityPropagationTrusts' \
        --header 'Content-Type: application/json' \
        --header "Authorization: Bearer $ACCESS_TOKEN" \
        --data '${local.trust_body}')

      TRUST_ID=$(echo "$TRUST_RESPONSE" | jq -r '.id // empty')
      if [ -n "$TRUST_ID" ] && [ "$TRUST_ID" != "null" ]; then
        echo "Trust created: $TRUST_ID"
      else
        ERROR_MESSAGE=$(echo "$TRUST_RESPONSE" | jq -r '.detail // .error // "Unknown"')
        if echo "$ERROR_MESSAGE" | grep -qi "same issuer already exists"; then
          echo "Trust already exists — updating it to use the new token exchange app..."

          # Find the existing trust ID by issuer
          ISSUER=$(echo '${local.trust_body}' | jq -r '.issuer')
          EXISTING=$(curl --silent \
            "${local.identity_domain_url}/admin/v1/IdentityPropagationTrusts?filter=issuer+eq+%22$ISSUER%22" \
            --header "Authorization: Bearer $ACCESS_TOKEN")
          EXISTING_ID=$(echo "$EXISTING" | jq -r '.Resources[0].id // empty')

          if [ -z "$EXISTING_ID" ] || [ "$EXISTING_ID" = "null" ]; then
            echo "Could not find existing trust for issuer $ISSUER" >&2
            exit 1
          fi

          # Build PATCH body to update the existing trust with the new token exchange app.
          # Extract individual values from the trust body to avoid complex jq expressions
          # that break under Terraform heredoc shell escaping.
          NEW_CLIENT=$(echo '${local.trust_body}' | jq -r '.oauthClients[0]')
          JWKS_URL=$(echo '${local.trust_body}' | jq -r '.publicKeyEndpoint')

          if [ '${local.is_upst}' = 'true' ]; then
            NEW_USER_ID=$(echo '${local.trust_body}' | jq -r '.impersonationServiceUsers[0].value')
            NEW_RULE=$(echo '${local.trust_body}' | jq -r '.impersonationServiceUsers[0].rule')
            PATCH_BODY='{"schemas":["urn:ietf:params:scim:api:messages:2.0:PatchOp"],"Operations":[{"op":"replace","path":"oauthClients","value":["'"$NEW_CLIENT"'"]},{"op":"replace","path":"publicKeyEndpoint","value":"'"$JWKS_URL"'"},{"op":"replace","path":"impersonationServiceUsers","value":[{"rule":"'"$NEW_RULE"'","value":"'"$NEW_USER_ID"'"}]}]}'
          else
            PATCH_BODY='{"schemas":["urn:ietf:params:scim:api:messages:2.0:PatchOp"],"Operations":[{"op":"replace","path":"oauthClients","value":["'"$NEW_CLIENT"'"]},{"op":"replace","path":"publicKeyEndpoint","value":"'"$JWKS_URL"'"}]}'
          fi

          PATCH_RESPONSE=$(curl --silent --location \
            --request PATCH \
            "${local.identity_domain_url}/admin/v1/IdentityPropagationTrusts/$EXISTING_ID" \
            --header 'Content-Type: application/json' \
            --header "Authorization: Bearer $ACCESS_TOKEN" \
            --data "$PATCH_BODY")

          UPDATED_ID=$(echo "$PATCH_RESPONSE" | jq -r '.id // empty')
          if [ -n "$UPDATED_ID" ] && [ "$UPDATED_ID" != "null" ]; then
            echo "Trust updated: $UPDATED_ID"
          else
            echo "Trust update failed: $(echo "$PATCH_RESPONSE" | jq -r '.detail // .error // "Unknown"')" >&2
            exit 1
          fi
        else
          echo "Trust creation failed: $ERROR_MESSAGE" >&2
          exit 1
        fi
      fi

    EOT
  }

  depends_on = [oci_identity_domains_grant.admin_app_domain_admin_grant]
}

