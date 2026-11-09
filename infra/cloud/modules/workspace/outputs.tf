output "bucket_name" {
  value = cloudflare_r2_bucket.storage.name
}

output "hyperdrive_id" {
  description = "Goes in the hosted wrangler config's HYPERDRIVE binding. Null until database is set."
  value       = one(cloudflare_hyperdrive_config.database[*].id)
}

output "wrangler_vars" {
  description = "Non-secret Worker variables for the hosted wrangler configs."
  value = {
    ENVIRONMENT      = var.environment
    STORAGE_ENDPOINT = "https://${var.account_id}.r2.cloudflarestorage.com"
    STORAGE_BUCKET   = cloudflare_r2_bucket.storage.name
    STORAGE_REGION   = "auto"
  }
}

output "worker_domains" {
  value = { for k, d in cloudflare_workers_custom_domain.worker : k => d.hostname }
}
