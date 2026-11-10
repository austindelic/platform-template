# Account resources the Workers bind to. The Worker scripts, their bindings and their secrets
# belong to Wrangler (apps/*/wrangler.jsonc, scripts/release.sh); this module creates only what
# they point at, plus their custom domains.

locals {
  name = "${var.project}-${var.environment}"
}

resource "cloudflare_r2_bucket" "storage" {
  account_id = var.account_id
  name       = local.name
  location   = var.bucket_location
  lifecycle { prevent_destroy = true }
}

# Private bucket: no r2.dev URL. The app reads and writes it with an R2 S3 API token scoped to
# this bucket and serves files through its own signed routes.
resource "cloudflare_r2_managed_domain" "storage" {
  account_id  = var.account_id
  bucket_name = cloudflare_r2_bucket.storage.name
  enabled     = false
}

# Encrypted database dumps (scripts/backup.sh). Locks stop a dump being deleted or overwritten, even with an admin
# token, until it is old enough; expiry then removes it. The storage bucket has no lock: the app deletes its own files,
# and its second copy is the versioned B2 bucket.
resource "cloudflare_r2_bucket" "backups" {
  count      = var.backups == null ? 0 : 1
  account_id = var.account_id
  name       = "${var.project}-backups-${var.environment}"
  location   = var.bucket_location
  lifecycle { prevent_destroy = true }
}

resource "cloudflare_r2_managed_domain" "backups" {
  count       = var.backups == null ? 0 : 1
  account_id  = var.account_id
  bucket_name = cloudflare_r2_bucket.backups[0].name
  enabled     = false
}

resource "cloudflare_r2_bucket_lock" "backups" {
  count       = var.backups == null ? 0 : 1
  account_id  = var.account_id
  bucket_name = cloudflare_r2_bucket.backups[0].name
  rules = [
    {
      id        = "daily"
      enabled   = true
      prefix    = "daily/"
      condition = { type = "Age", max_age_seconds = var.backups.daily_lock_days * 86400 }
    },
    {
      id        = "monthly"
      enabled   = true
      prefix    = "monthly/"
      condition = { type = "Age", max_age_seconds = var.backups.monthly_lock_days * 86400 }
    },
  ]
}

resource "cloudflare_r2_bucket_lifecycle" "backups" {
  count       = var.backups == null ? 0 : 1
  account_id  = var.account_id
  bucket_name = cloudflare_r2_bucket.backups[0].name
  rules = [
    # Listed in id order, as Cloudflare returns them, so a plan shows no false change.
    {
      id                                 = "abort-stale-uploads"
      enabled                            = true
      conditions                         = { prefix = "" }
      abort_multipart_uploads_transition = { condition = { type = "Age", max_age = 7 * 86400 } }
    },
    {
      id                        = "expire-daily"
      enabled                   = true
      conditions                = { prefix = "daily/" }
      delete_objects_transition = { condition = { type = "Age", max_age = var.backups.daily_keep_days * 86400 } }
    },
    {
      id                        = "expire-monthly"
      enabled                   = true
      conditions                = { prefix = "monthly/" }
      delete_objects_transition = { condition = { type = "Age", max_age = var.backups.monthly_keep_days * 86400 } }
    },
  ]
}

resource "cloudflare_hyperdrive_config" "database" {
  count      = var.database == null ? 0 : 1
  account_id = var.account_id
  name       = local.name
  origin = {
    host     = var.database.host
    port     = var.database.port
    database = var.database.name
    user     = var.database.user
    scheme   = var.database.scheme
    password = var.database_password
  }
  # Off by default: apps usually read their own writes.
  caching                 = { disabled = !var.database.caching }
  origin_connection_limit = var.database.max_conn

  lifecycle {
    precondition {
      condition     = var.database_password != null
      error_message = "Set TF_VAR_database_password before creating the Hyperdrive config."
    }
  }
}

resource "cloudflare_workers_custom_domain" "worker" {
  for_each   = var.worker_domains
  account_id = var.account_id
  zone_id    = each.value.zone_id
  hostname   = each.value.hostname
  service    = each.value.service
}
