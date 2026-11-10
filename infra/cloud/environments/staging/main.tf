locals {
  environment = "staging"
  web_worker  = "${var.project}-web-${local.environment}"
  jobs_worker = "${var.project}-jobs-${local.environment}"

  # With manage_credentials and a PlanetScale branch, Hyperdrive logs in as a role OpenTofu mints and rotates
  # (modules/credentials); otherwise database.user and TF_VAR_database_password.
  hyperdrive_username = one(module.credentials[*].hyperdrive_username)
  hyperdrive_password = one(module.credentials[*].hyperdrive_password)
  database            = var.database == null || local.hyperdrive_username == null ? var.database : merge(var.database, { user = local.hyperdrive_username })
}

# The team domain (<team>.cloudflareaccess.com) issues the JWTs apps/web verifies.
data "cloudflare_zero_trust_organization" "access" {
  account_id = var.account_id
}

module "workspace" {
  source = "../../modules/workspace"

  account_id        = var.account_id
  project           = var.project
  environment       = local.environment
  bucket_location   = var.bucket_location
  queues            = var.queues
  database          = local.database
  database_password = local.hyperdrive_password != null ? local.hyperdrive_password : var.database_password
  worker_domains = var.attach_worker_domains ? {
    web = { hostname = var.web_hostname, service = local.web_worker, zone_id = var.web_zone_id }
  } : {}
}

# The whole web host sits behind Cloudflare Access until the app has its own authentication.
module "web_access" {
  source = "../../modules/access"

  account_id            = var.account_id
  name                  = "${var.project} (${local.environment})"
  hostname              = var.web_hostname
  identity_provider_id  = var.identity_provider_id
  allowed_email_domains = var.allowed_email_domains
  allowed_emails        = var.allowed_emails
  machine_paths         = var.machine_paths
  service_tokens        = var.service_tokens
}

# Tokens, keys, database roles and generated secrets for this environment, each with an expiry
# (modules/credentials). Off until manage_credentials; infra/secrets reads the `secrets` output and
# writes it to Infisical. Applied by a person, never in CI.
module "credentials" {
  source = "../../modules/credentials"
  count  = var.manage_credentials ? 1 : 0

  account_id          = var.account_id
  project             = var.project
  environment         = local.environment
  storage_bucket_name = module.workspace.bucket_name
  backups_bucket_name = null
  app_secrets         = var.app_secrets
  deploy_permission_groups = distinct(concat(
    coalesce(var.deploy_permission_groups, ["Workers Scripts Write", "Workers R2 Storage Write", "Hyperdrive Write", "Account Settings Read"]),
    length(var.queues) > 0 ? ["Queues Write"] : [],
  ))
  planetscale             = var.planetscale
  migration_role_ttl_days = var.migration_role_ttl_days
}
