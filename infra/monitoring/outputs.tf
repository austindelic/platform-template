output "heartbeat_secret_names" {
  description = "Infisical secret name per heartbeat. Names only, safe to print."
  value       = { for k, h in local.heartbeats : k => h.secret }
}

# Read by infra/secrets through terraform_remote_state, in the same shape as the environment roots:
# destination ("runtime/<Worker folder>" of <app>-runtime-prod, or "backups") to name to value.
locals {
  secrets = { for dest in distinct(concat(
    [for h in values(local.heartbeats) : h.dest],
    [for p in values(local.sentry_projects) : "runtime/${p.folder}"],
    )) : dest => merge(
    { for k, h in local.heartbeats : h.secret => betteruptime_heartbeat.job[k].url if h.dest == dest },
    { for slug, p in local.sentry_projects : "SENTRY_DSN" => sentry_key.app[slug].dsn["public"] if "runtime/${p.folder}" == dest },
  ) }
}

output "secrets" {
  description = "Sensitive. DSNs and heartbeat URLs per Infisical destination, for infra/secrets."
  sensitive   = true
  value       = local.secrets
}

output "secret_names" {
  description = "The same shape as secrets, names only. Safe to print."
  value       = { for dest, m in local.secrets : dest => nonsensitive(sort(keys(m))) }
}
