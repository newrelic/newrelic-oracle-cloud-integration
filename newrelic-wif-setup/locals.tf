locals {
  identity_domain_url = trimsuffix(data.oci_identity_domains.domain.domains[0].url, ":443")
  suffix              = "orm"

  is_upst = var.trust_type == "UPST"
  is_rpst = var.trust_type == "RPST"

  resource_prefix = var.resource_prefix != "" ? var.resource_prefix : "newrelic"

  impersonating_resource = "newrelic-integration"

  newrelic_config = {
    US = {
      issuer_name      = "newrelic-oci-us-production-issuer"
      subject_name     = "newrelic-oci-us-production-user"
      rpst_issuer_name = "newrelic-oci-us-production-rpst-issuer"
      public_jwks_url  = "https://publickeys.newrelic.com/r/oci-cmp/us/c5623ba5-1cc7-491a-8ec3-eeee809374f7/jwks.json"
    }
    EU = {
      issuer_name      = "newrelic-oci-eu-production-issuer"
      subject_name     = "newrelic-oci-eu-production-user"
      rpst_issuer_name = "newrelic-oci-eu-production-rpst-issuer"
      public_jwks_url  = "https://publickeys.eu.newrelic.com/r/oci-cmp/eu/f923dba9-84a8-491c-b714-6c0e61b90c5b/jwks.json"
    }
    JP = {
      issuer_name      = "newrelic-oci-jp-production-issuer"
      subject_name     = "newrelic-oci-jp-production-user"
      rpst_issuer_name = "newrelic-oci-jp-production-rpst-issuer"
      public_jwks_url  = "https://publickeys.jp.newrelic.com/r/oci-cmp/jp/89625529-5f3e-47b8-a13a-25229f85989d/jwks.json"
    }
  }[var.newrelic_region]
}
