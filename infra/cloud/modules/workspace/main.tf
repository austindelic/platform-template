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
