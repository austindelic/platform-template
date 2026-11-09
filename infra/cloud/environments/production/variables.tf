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
