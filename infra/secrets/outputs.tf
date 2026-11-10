# Metadata only. No value is ever output.
output "secret_names" {
  description = "Every secret this root writes, as <source root>/<destination>/<name>. Safe to print."
  value       = sort(keys(local.secrets))
}

output "credentials_expire" {
  description = "When each environment's minted tokens, keys and roles expire and are next replaced. Calendar a reminder."
  value = {
    staging    = try(local.sources.staging.credentials_expire, null)
    production = try(local.sources.production.credentials_expire, null)
  }
}
