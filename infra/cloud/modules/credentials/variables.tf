variable "account_id" {
  type        = string
  description = "Cloudflare account that owns the tokens' resources."
  validation {
    condition     = can(regex("^[a-f0-9]{32}$", var.account_id))
    error_message = "account_id must be a 32-character Cloudflare account ID."
  }
}

variable "project" {
  type        = string
  description = "Project slug used in token, key and role names, for example \"platform-starter\"."
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.project))
    error_message = "project must be lower case letters, digits and hyphens."
  }
}

variable "environment" {
  type        = string
  description = "staging or production. Every token, key and role belongs to one environment."
  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "environment must be staging or production."
  }
}

variable "storage_bucket_name" {
  type        = string
  description = "The app's private R2 bucket (STORAGE_BUCKET)."
}

variable "backups_bucket_name" {
  type        = string
  default     = null
  description = "The locked R2 backups bucket. Null mints no backup keys or role (staging)."
}

variable "rotation_days" {
  type = object({
    tokens = optional(number, 90)
    roles  = optional(number, 60)
  })
  default     = {}
  description = "How often a plain apply replaces the Cloudflare tokens and B2 key (tokens) and the PlanetScale roles (roles)."
  validation {
    condition     = var.rotation_days.tokens >= 7 && var.rotation_days.tokens <= 365 && var.rotation_days.roles >= 7 && var.rotation_days.roles <= 365
    error_message = "Rotate between every 7 and 365 days."
  }
}

variable "grace_days" {
  type        = number
  default     = 14
  description = "Days a token, key or role outlives its scheduled replacement, so a late apply breaks nothing."
  validation {
    condition     = var.grace_days >= 1 && var.grace_days <= 90
    error_message = "Grace must be between 1 and 90 days."
  }
}

variable "deploy_permission_groups" {
  type = list(string)
  default = [
    "Workers Scripts Write", "Workers R2 Storage Write", "Hyperdrive Write", "Account Settings Read",
  ]
  description = "Cloudflare permission group names for the deploy token (scripts/release.sh: wrangler deploy). Add what new bindings need, such as \"Queues Write\", \"Workers Containers Write\" or \"Email Sending Write\". Names must exist in the account; plan fails otherwise."
}

variable "storage_permission_group" {
  type        = string
  default     = "Workers R2 Storage Bucket Item Write"
  description = "Permission group for the app's R2 key, scoped to the storage bucket only."
}

variable "backups_read_permission_group" {
  type        = string
  default     = "Workers R2 Storage Bucket Item Read"
  description = "Permission group for the backups key on the storage bucket (the copy job reads it)."
}

variable "planetscale" {
  type = object({
    organization     = string
    database         = string # PlanetScale database slug
    branch           = optional(string, "main")
    database_name    = string # the Postgres database on that branch
    dedicated_branch = optional(bool, false)
  })
  default     = null
  description = "The PlanetScale branch for the Hyperdrive and backup roles. Null mints no roles. Staging mints roles only with dedicated_branch = true: a minted role inherits only built-in roles (pg_read_all_data, pg_write_all_data), which reach every database on its branch, so staging must not share production's branch."
}

variable "hyperdrive_role_inherits" {
  type        = list(string)
  default     = ["pg_read_all_data", "pg_write_all_data"]
  description = "Built-in Postgres roles the Hyperdrive role inherits: data in and out, no schema changes (migrations use their own role)."
  validation {
    condition     = !contains(var.hyperdrive_role_inherits, "postgres")
    error_message = "The Hyperdrive role never inherits the admin role."
  }
}

variable "migration_role_ttl_days" {
  type        = number
  default     = 7
  description = "Lifetime of the PlanetScale migration role (DDL, inherits postgres). It expires by itself and the first apply after that mints the next one, so before a release that finds it lapsed apply this root, then infra/secrets."
  validation {
    condition     = var.migration_role_ttl_days >= 1 && var.migration_role_ttl_days <= 30
    error_message = "The migration role lives between 1 and 30 days."
  }
}

variable "b2_bucket_name" {
  type        = string
  default     = null
  description = "The versioned, Object Lock B2 bucket the copy job writes to (BACKUP_B2_BUCKET). Null mints no B2 key."
}

variable "b2_capabilities" {
  type        = list(string)
  default     = ["listBuckets", "listFiles", "readFiles", "writeFiles"]
  description = "What the B2 copy key can do. No deleteFiles: rclone hides files instead of deleting them."
  validation {
    condition     = length(setintersection(var.b2_capabilities, ["deleteFiles", "deleteBuckets", "writeBuckets", "writeKeys", "deleteKeys", "bypassGovernance", "writeFileRetentions", "writeBucketRetentions"])) == 0
    error_message = "The B2 copy key never deletes, changes buckets, keys or retention."
  }
}

variable "app_secrets" {
  type        = map(list(string))
  default     = {}
  description = "Generated app secrets (48 random characters) and the Worker folders that receive each, for example { SESSION_SECRET = [\"web\"] }. They never rotate on a schedule; replace one with tofu apply -replace."
  validation {
    condition     = alltrue([for name, folders in var.app_secrets : can(regex("^[A-Z][A-Z0-9_]*$", name)) && length(folders) > 0])
    error_message = "Secret names are UPPER_SNAKE_CASE and each goes to at least one folder."
  }
}

variable "storage_key_folders" {
  type        = list(string)
  default     = ["web", "worker"]
  description = "Worker folders of <app>-runtime-<env> that get the bucket-scoped R2 key (STORAGE_ACCESS_KEY, STORAGE_SECRET_KEY)."
}
