locals {
  environment = "production"
  web_worker  = "${var.project}-web-${local.environment}"
  jobs_worker = "${var.project}-jobs-${local.environment}"
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
  database          = var.database
  database_password = var.database_password
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
