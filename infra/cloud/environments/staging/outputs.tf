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
