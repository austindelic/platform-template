variable "account_id" {
  type        = string
  description = "Cloudflare account that owns the Workers, R2 bucket and Hyperdrive config."
  validation {
    condition     = can(regex("^[a-f0-9]{32}$", var.account_id))
    error_message = "account_id must be a 32-character Cloudflare account ID."
  }
}

variable "project" {
  type        = string
  description = "Project slug used in resource names, for example \"platform-starter\"."
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.project))
    error_message = "project must be lower case letters, digits and hyphens."
  }
}

variable "environment" {
  type        = string
  description = "staging or production. Used in resource names and the ENVIRONMENT Worker variable."
  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "environment must be staging or production."
  }
}

variable "bucket_location" {
  type        = string
  default     = null
  description = "Optional R2 location hint, for example \"oc\" or \"wnam\"."
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

variable "worker_domains" {
  type = map(object({
    hostname = string
    service  = string
    zone_id  = string
  }))
  default     = {}
  description = "Custom domains per Worker. Attach only after the first Wrangler deploy created the Worker and its Access application exists."
}
