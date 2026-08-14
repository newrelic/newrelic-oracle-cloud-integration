output "oci_domain_url" {
  description = "Paste this into New Relic's OCI Domain URL field"
  value       = regex("^(https?://[^:]+)", local.identity_domain_url)[0]
}

output "client_id" {
  description = "Paste this into New Relic's OCI Client ID field"
  value       = oci_identity_domains_app.token_exchange_app.name
}

# sensitive = true is intentionally omitted. ORM renders sensitive outputs as
# empty string in the Outputs tab UI, making the value inaccessible to customers.
# ORM job logs are only visible to authorized stack users.
output "client_secret" {
  description = "Paste this into New Relic's OCI Client Secret field"
  value       = null_resource.trust_setup.triggers["client_secret"]
}

output "trust_type" {
  description = "Paste this into New Relic's Trust Type field"
  value       = var.trust_type
}
