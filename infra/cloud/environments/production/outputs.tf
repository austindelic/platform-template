output "web_url" {
  value = module.web_access.url
}

output "wrangler" {
  description = "Values for the env blocks of apps/web and apps/worker wrangler.jsonc. Secrets are never output here."
  value = {
    web = {
      name          = local.web_worker
      hyperdrive_id = module.workspace.hyperdrive_id
      jobs_service  = local.jobs_worker
      vars = merge(module.workspace.wrangler_vars, {
        CF_ACCESS_TEAM_DOMAIN = "https://${data.cloudflare_zero_trust_organization.access.auth_domain}"
        CF_ACCESS_AUD         = join(",", module.web_access.audiences)
      })
    }
    worker = {
      name = local.jobs_worker
      vars = module.workspace.wrangler_vars
    }
  }
}

output "service_token_client_ids" {
  value = module.web_access.service_token_client_ids
}

output "service_token_client_secrets" {
  description = "Read once with `tofu output -json service_token_client_secrets`, put in Infisical, never commit."
  sensitive   = true
  value       = module.web_access.service_token_client_secrets
}

output "secrets" {
  description = "Sensitive. Secret values per Infisical destination, for infra/secrets. Null until manage_credentials is applied."
  sensitive   = true
  value       = one(module.credentials[*].secrets)
}

output "secret_names" {
  description = "Secret names per Infisical destination. Safe to print."
  value       = one(module.credentials[*].secret_names)
}

output "credentials_expire" {
  description = "When the minted tokens, keys and roles expire and are next replaced. Safe to print."
  value       = one(module.credentials[*].expires)
}

output "planetscale_branch" {
  description = "The PlanetScale branch the minted roles are on, or null."
  value       = one(module.credentials[*].planetscale_branch)
}

output "backups_bucket" {
  description = "Where the nightly job writes encrypted dumps, or null."
  value       = module.workspace.backups_bucket
}
