# Read by infra/secrets through terraform_remote_state. Keys are Infisical destinations: "runtime/<folder>" is a
# folder of <app>-runtime-<env> (one per Worker), "deploy" is <app>-deploy-<env>, "backups" is <app>-backups-prod.

locals {
  storage_key = { id = cloudflare_account_token.storage.id, secret = sha256(cloudflare_account_token.storage.value) }

  backups_db_url = local.mint_backups ? format(
    "postgresql://%s:%s@%s:5432/%s?sslmode=verify-full&sslrootcert=system",
    urlencode(planetscale_postgres_branch_role.backups[0].username),
    urlencode(planetscale_postgres_branch_role.backups[0].password),
    planetscale_postgres_branch_role.backups[0].access_host_url,
    var.planetscale.database_name,
  ) : null

  # options=-c role=postgres: the session acts as postgres, so new tables and indexes belong to postgres. A literal %20:
  # urlencode() writes a space as "+", which libpq and node-postgres do not decode.
  migration_db_url = local.mint_migration ? format(
    "postgresql://%s:%s@%s:5432/%s?sslmode=verify-full&sslrootcert=system&options=-c%%20role%%3Dpostgres",
    urlencode(planetscale_postgres_branch_role.migrate[0].username),
    urlencode(planetscale_postgres_branch_role.migrate[0].password),
    planetscale_postgres_branch_role.migrate[0].access_host_url,
    var.planetscale.database_name,
  ) : null

  runtime_folders = distinct(concat(var.storage_key_folders, flatten(values(var.app_secrets))))
  runtime = { for folder in local.runtime_folders : "runtime/${folder}" => merge(
    contains(var.storage_key_folders, folder) ? {
      STORAGE_ACCESS_KEY = local.storage_key.id
      STORAGE_SECRET_KEY = local.storage_key.secret
    } : {},
    { for name, folders in var.app_secrets : name => random_password.app[name].result if contains(folders, folder) },
  ) }

  # One folder per Worker (the R2 key where storage_key_folders says, plus each generated app secret), then the
  # deploy and backups projects.
  secrets = merge(local.runtime, {
    # Without a minted migration role DATABASE_URL_DIRECT stays a login set by hand in <app>-deploy-<env>, and nothing
    # here writes that name.
    deploy = merge(
      {
        CLOUDFLARE_API_TOKEN  = cloudflare_account_token.deploy.value
        CLOUDFLARE_ACCOUNT_ID = var.account_id
      },
      local.migration_db_url == null ? {} : { DATABASE_URL_DIRECT = local.migration_db_url },
    )
    backups = var.backups_bucket_name == null ? {} : merge(
      {
        BACKUP_R2_ENDPOINT          = "https://${var.account_id}.r2.cloudflarestorage.com"
        BACKUP_R2_ACCESS_KEY_ID     = cloudflare_account_token.backups[0].id
        BACKUP_R2_SECRET_ACCESS_KEY = sha256(cloudflare_account_token.backups[0].value)
      },
      local.backups_db_url == null ? {} : { DATABASE_URL_DIRECT = local.backups_db_url },
      var.b2_bucket_name == null ? {} : {
        BACKUP_B2_BUCKET          = var.b2_bucket_name
        BACKUP_B2_KEY_ID          = b2_application_key.copy[0].application_key_id
        BACKUP_B2_APPLICATION_KEY = b2_application_key.copy[0].application_key
      },
    )
  })
}

output "secrets" {
  description = "Sensitive. Secret name to value per Infisical destination. Written by infra/secrets, never read by hand."
  sensitive   = true
  value       = local.secrets
}

output "secret_names" {
  description = "The same shape as secrets, names only. Safe to print."
  value       = { for dest, m in local.secrets : dest => nonsensitive(sort(keys(m))) }
}

output "expires" {
  description = "When the minted tokens, key and roles stop working and are next replaced. Safe to print."
  value = {
    tokens           = local.expires_on
    tokens_rotate_at = time_rotating.tokens.rotation_rfc3339
    roles_ttl_days   = var.rotation_days.roles + var.grace_days
    roles_rotate_at  = time_rotating.roles.rotation_rfc3339
    # The migration role expires when it is next replaced: before a release after this date, apply, then infra/secrets.
    migration_role_expires = local.mint_migration ? time_rotating.migration[0].rotation_rfc3339 : null
  }
}

output "hyperdrive_username" {
  description = "The minted Hyperdrive login, or null when no role is minted (the environment keeps database_password)."
  value       = local.mint_roles ? planetscale_postgres_branch_role.app[0].username : null
}

output "hyperdrive_password" {
  description = "The minted Hyperdrive login's password. Goes straight into the Hyperdrive config."
  sensitive   = true
  value       = local.mint_roles ? planetscale_postgres_branch_role.app[0].password : null
}

output "planetscale_branch" {
  description = "The PlanetScale branch the minted roles are on, or null when none are minted. infra/secrets refuses staging and production roles on one branch."
  value       = local.mint_roles ? "${var.planetscale.organization}/${var.planetscale.database}/${var.planetscale.branch}" : null
}
