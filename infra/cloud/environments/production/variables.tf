variable "state_passphrase" {
  type        = string
  sensitive   = true
  description = "State and plan encryption passphrase. TF_VAR_state_passphrase from the password manager; never in a tfvars file."
  validation {
    condition     = length(var.state_passphrase) >= 16
    error_message = "state_passphrase must be at least 16 characters."
  }
}

variable "account_id" {
  type        = string
  description = "Cloudflare account ID (32 hex characters)."
}

variable "project" {
  type        = string
  default     = "platform-starter"
  description = "Project slug: resource and Worker names are <project>-<app>-<environment>."
}

variable "identity_provider_id" {
  type        = string
  description = "Access identity provider ID of the Google login."
}

variable "allowed_email_domains" {
  type        = list(string)
  description = "Email domains allowed into the web app, for example [\"example.com\"]."
}

variable "allowed_emails" {
  type        = list(string)
  default     = []
  description = "Extra individual addresses allowed in. They still sign in with the identity provider."
}

variable "web_hostname" {
  type        = string
  description = "Hostname of the web app, for example app.example.com."
}

variable "web_zone_id" {
  type        = string
  default     = null
  description = "Zone containing web_hostname. Needed once attach_worker_domains is true."
}

variable "machine_paths" {
  type = list(object({
    path = string
    mode = string
  }))
  default = [
    # Liveness for uptime monitors: a fixed "ok" with no database, auth or secrets.
    { path = "healthz", mode = "bypass" },
  ]
  description = "Paths machines reach without a browser sign-in (modules/access)."
}

variable "service_tokens" {
  type        = map(object({ duration = optional(string, "8760h") }))
  default     = {}
  description = "Service tokens for service_token machine paths, one per caller pool."
}

variable "bucket_location" {
  type        = string
  default     = null
  description = "Optional R2 location hint, for example \"oc\"."
}

variable "database" {
  type = object({
    host     = string
    port     = optional(number, 5432)
    name     = string
    user     = string
    scheme   = optional(string, "postgres")
    caching  = optional(bool, false)
    max_conn = optional(number)
  })
  default     = null
  description = "Postgres origin for Hyperdrive; null until the database exists."
}

variable "database_password" {
  type        = string
  default     = null
  sensitive   = true
  description = "TF_VAR_database_password from the humans-only infra project; never in a tfvars file."
}

variable "attach_worker_domains" {
  type        = bool
  default     = false
  description = "Attach the custom domain to the web Worker. Only after the first Wrangler deploy and with the Access application in place."
}

variable "manage_credentials" {
  type        = bool
  default     = false
  description = "Mint this environment's Cloudflare deploy token, bucket-scoped R2 key, generated app secrets and (with planetscale) database roles, each with an expiry and rotation (modules/credentials), for infra/secrets to write to Infisical. Needs a minter token that holds every permission it hands on. Never in CI."
}

variable "app_secrets" {
  type        = map(list(string))
  default     = {}
  description = "Generated app secrets and the Worker folders that get each, for example { SESSION_SECRET = [\"web\"] } (modules/credentials)."
}

variable "deploy_permission_groups" {
  type        = list(string)
  default     = null
  description = "Cloudflare permission groups for the minted deploy token. Null uses the module default (Workers, R2, Hyperdrive, account settings)."
}

variable "planetscale" {
  type = object({
    organization     = string
    database         = string
    branch           = optional(string, "main")
    database_name    = string
    dedicated_branch = optional(bool, false)
  })
  default     = null
  description = "PlanetScale branch for minted Hyperdrive and migration roles (with manage_credentials). Null keeps database.user and TF_VAR_database_password, and a DATABASE_URL_DIRECT set by hand."
}

variable "migration_role_ttl_days" {
  type        = number
  default     = 7
  description = "Lifetime of the minted migration role, in days. A release after it lapses fails at migrations: apply this root, then infra/secrets, and re-run."
}

variable "backups_enabled" {
  type        = bool
  default     = false
  description = "Create the locked R2 backups bucket, and with manage_credentials mint its R2 key (and a read-only database role with planetscale), for .github/workflows/backups.yml."
}

variable "b2_bucket_name" {
  type        = string
  default     = null
  description = "An existing versioned, Object Lock B2 bucket for the second copy (BACKUP_B2_BUCKET). With manage_credentials, mints a copy-only key for it. Null skips the copy."
}

variable "queues" {
  type        = set(string)
  default     = []
  description = "Queue keys for apps/worker (infra/cloud/README.md, Queues). Each gets a dead-letter queue; the minted deploy token gains Queues Write."
}
