# Credentials one environment of the app needs, minted with an expiry and exposed as sensitive outputs. The
# environment root passes the Hyperdrive login straight to Hyperdrive; the laptop-only infra/secrets root reads the
# `secrets` output through terraform_remote_state and writes each map into the Infisical project and folder that
# matches who reads it (infra/cloud/README.md). Nothing here is a literal or pasted by a person.

locals {
  account_resource = jsonencode({ "com.cloudflare.api.account.${var.account_id}" = "*" })
  bucket_resource = { for b in compact([var.storage_bucket_name, var.backups_bucket_name]) :
    b => jsonencode({ "com.cloudflare.edge.r2.bucket.${var.account_id}_default_${b}" = "*" })
  }
  # Cloudflare lists some names twice, once per scope (for example "Access: Apps and Policies Write" for accounts and
  # for zones). Every token here is account- or bucket-scoped, so drop the zone-scoped copies before keying by name.
  groups = {
    for g in data.cloudflare_account_api_token_permission_groups_list.all.result : g.name => g.id...
    if !contains(g.scopes, "com.cloudflare.api.account.zone")
  }
  group = { for name, ids in local.groups : name => ids[0] }

  # A token or key is replaced by the first apply after its rotation date and stops working grace_days after that
  # date, so one missed apply breaks nothing. The backups role does the same through its ttl.
  expires_on   = timeadd(time_rotating.tokens.rotation_rfc3339, "${var.grace_days * 24}h")
  token_suffix = "${var.environment} (replace by ${formatdate("YYYY-MM-DD", time_rotating.tokens.rotation_rfc3339)})"
  role_suffix  = formatdate("YYYYMMDD", time_rotating.roles.rfc3339)
  role_ttl     = (var.rotation_days.roles + var.grace_days) * 86400

  # A minted role can inherit only built-in roles such as pg_read_all_data, which reach every database on its branch,
  # so staging gets minted roles only on a branch of its own (never production's).
  mint_roles   = var.planetscale != null && (var.environment == "production" || try(var.planetscale.dedicated_branch, false))
  mint_backups = local.mint_roles && var.backups_bucket_name != null
  # The migration role inherits postgres, the admin, which reaches every database on its branch, so it follows the
  # same rule: production, or staging on a branch of its own. Staging on the shared branch keeps its own login.
  mint_migration = local.mint_roles
}

data "cloudflare_account_api_token_permission_groups_list" "all" {
  account_id = var.account_id
}

resource "time_rotating" "tokens" {
  rotation_days = var.rotation_days.tokens
}

resource "time_rotating" "roles" {
  rotation_days = var.rotation_days.roles
}

# The migration role lives only a few days: the first apply after it lapses mints the next one.
resource "time_rotating" "migration" {
  count         = local.mint_migration ? 1 : 0
  rotation_days = var.migration_role_ttl_days
}

# --- Cloudflare tokens --------------------------------------------------------------------------------------------
# Account-owned, one per purpose and environment, each with an expiry. Created by the minter token, which can only
# grant permissions it holds itself.

# What CI runs wrangler with (scripts/release.sh). One per environment.
resource "cloudflare_account_token" "deploy" {
  account_id = var.account_id
  name       = "${var.project} deploy ${local.token_suffix}"
  expires_on = local.expires_on
  policies = [{
    effect            = "allow"
    resources         = local.account_resource
    permission_groups = [for n in var.deploy_permission_groups : { id = local.group[n] }]
  }]
  lifecycle { replace_triggered_by = [time_rotating.tokens] }
}

# The app's R2 S3 key: the access key ID is the token ID, the secret is the SHA-256 of the value.
resource "cloudflare_account_token" "storage" {
  account_id = var.account_id
  name       = "${var.project} storage ${local.token_suffix}"
  expires_on = local.expires_on
  policies = [{
    effect            = "allow"
    resources         = local.bucket_resource[var.storage_bucket_name]
    permission_groups = [{ id = local.group[var.storage_permission_group] }]
  }]
  lifecycle { replace_triggered_by = [time_rotating.tokens] }
}

# The backup job: read the storage bucket, write the backups bucket (scripts/backup.sh).
resource "cloudflare_account_token" "backups" {
  count      = var.backups_bucket_name == null ? 0 : 1
  account_id = var.account_id
  name       = "${var.project} backups ${local.token_suffix}"
  expires_on = local.expires_on
  policies = [
    {
      effect            = "allow"
      resources         = local.bucket_resource[var.storage_bucket_name]
      permission_groups = [{ id = local.group[var.backups_read_permission_group] }]
    },
    {
      effect            = "allow"
      resources         = local.bucket_resource[var.backups_bucket_name]
      permission_groups = [{ id = local.group[var.storage_permission_group] }]
    },
  ]
  lifecycle { replace_triggered_by = [time_rotating.tokens] }
}

# --- PlanetScale roles --------------------------------------------------------------------------------------------
# Never the default (admin) role. Each purpose has its own role, named by the day it was minted, so the new one
# exists before the old one is dropped. The plain role, not planetscale_postgres_redacted_branch_role: the redacted
# variant never returns the password, and both of these are delivered (to Hyperdrive and to Infisical).

# Hyperdrive's login for the Workers: reads and writes data, cannot change the schema. Rotated by apply; the
# environment root passes it to the Hyperdrive config, so no one ever holds the password. No ttl: an expired
# Hyperdrive login would take the app down, while a late rotation costs nothing.
resource "planetscale_postgres_branch_role" "app" {
  count           = local.mint_roles ? 1 : 0
  organization    = var.planetscale.organization
  database        = var.planetscale.database
  branch          = var.planetscale.branch
  name            = "${var.project}-${var.environment}-app-${local.role_suffix}"
  inherited_roles = var.hyperdrive_role_inherits
  lifecycle {
    create_before_destroy = true
    replace_triggered_by  = [time_rotating.roles]
  }
}

# The backup job's login (pg_dump): read-only, and it expires by itself even if nothing rotates it.
resource "planetscale_postgres_branch_role" "backups" {
  count           = local.mint_backups ? 1 : 0
  organization    = var.planetscale.organization
  database        = var.planetscale.database
  branch          = var.planetscale.branch
  name            = "${var.project}-${var.environment}-backups-${local.role_suffix}"
  inherited_roles = ["pg_read_all_data"]
  ttl             = local.role_ttl
  lifecycle {
    create_before_destroy = true
    replace_triggered_by  = [time_rotating.roles]
  }
}

# Schema changes: scripts/release.sh runs the migrations with it (DATABASE_URL_DIRECT in <app>-deploy-<env>, read by
# the CI identity). Inherits postgres, the only PlanetScale role with DDL on every table, and expires by itself after
# migration_role_ttl_days, so a leaked copy is short-lived. Its URL sets role=postgres for the session, so what a
# migration creates is owned by postgres, not by a dated role that will be dropped; successor hands anything left over
# to postgres when OpenTofu drops it.
resource "planetscale_postgres_branch_role" "migrate" {
  count           = local.mint_migration ? 1 : 0
  organization    = var.planetscale.organization
  database        = var.planetscale.database
  branch          = var.planetscale.branch
  name            = "${var.project}-${var.environment}-migrate-${formatdate("YYYYMMDD", time_rotating.migration[0].rfc3339)}"
  inherited_roles = ["postgres"]
  ttl             = var.migration_role_ttl_days * 86400
  successor       = "postgres"
  lifecycle {
    create_before_destroy = true
    replace_triggered_by  = [time_rotating.migration]
  }
}

# --- Backblaze B2 -------------------------------------------------------------------------------------------------
# The copy job's key (scripts/backup.sh copy): this bucket only, list, read and write, no delete. rclone hides
# replaced or removed files (a write), and the bucket's versioning and Object Lock keep every version.

data "b2_bucket" "copy" {
  count       = var.b2_bucket_name == null ? 0 : 1
  bucket_name = var.b2_bucket_name
}

resource "b2_application_key" "copy" {
  count    = var.b2_bucket_name == null ? 0 : 1
  key_name = "${var.project}-${var.environment}-copy-${formatdate("YYYYMMDD", time_rotating.tokens.rfc3339)}"
  # One bucket, not bucket_ids: B2 marks a bucket_ids key as multi-bucket, and the v1 API that rclone uses rejects it.
  bucket_id                 = data.b2_bucket.copy[0].bucket_id
  capabilities              = var.b2_capabilities
  valid_duration_in_seconds = (var.rotation_days.tokens + var.grace_days) * 86400
  lifecycle {
    create_before_destroy = true
    replace_triggered_by  = [time_rotating.tokens]
  }
}

# --- Generated app secrets ----------------------------------------------------------------------------------------
# They never rotate on a schedule: replacing one signs everyone out or voids outstanding links. Rotate deliberately
# with `tofu apply -replace='module.credentials[0].random_password.app["NAME"]'`.
resource "random_password" "app" {
  for_each = var.app_secrets
  length   = 48
  special  = false
}
