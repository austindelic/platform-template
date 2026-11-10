variable "state_passphrase" {
  type        = string
  sensitive   = true
  description = "Encrypts the state and plan files. TF_VAR_state_passphrase from the password manager; the same as the other roots."
  validation {
    condition     = length(var.state_passphrase) >= 16
    error_message = "state_passphrase must be at least 16 characters."
  }
}

variable "betteruptime_api_token" {
  type        = string
  default     = null
  sensitive   = true
  description = "Leave unset: the provider reads BETTERUPTIME_API_TOKEN. Only offline tests set it."
}

variable "project" {
  type        = string
  default     = "platform-starter"
  description = "Project slug; monitors and heartbeats are named <project>-prod-<job>, Sentry projects <project> and <project>-jobs."
}

variable "web_url" {
  type        = string
  description = "Production web origin, for example https://app.example.com. The monitor checks <web_url>/healthz."
  validation {
    condition     = can(regex("^https://[^/]+$", var.web_url))
    error_message = "web_url is an https origin with no path."
  }
}

variable "enable_health_monitor" {
  type        = bool
  default     = false
  description = "Run the /healthz monitor. Leave false until production is deployed and the Access bypass for /healthz is applied, or it fails and pages."
}

variable "enable_cron_heartbeat" {
  type        = bool
  default     = false
  description = "Watch the jobs Worker's sweep schedule. Leave false until the cron is confirmed running and HEARTBEAT_URL_SWEEP is on the Worker."
}

variable "backups_enabled" {
  type        = bool
  default     = false
  description = "Create the backup dump, copy and restore heartbeats (.github/workflows/backups.yml)."
}

variable "public_status" {
  type        = bool
  default     = false
  description = "List the web monitor on a shared status page (needs status_page_id and status_page_section_id)."
}

variable "status_page_id" {
  type        = string
  default     = null
  description = "Id of an existing Better Stack status page, often owned by a shared platform root. Not a secret."
}

variable "status_page_section_id" {
  type        = number
  default     = null
  description = "Id of the status page section the entry goes in. Not a secret."
}

variable "sentry_organization" {
  type        = string
  default     = null
  description = "Slug of the existing Sentry organisation. Null creates no Sentry projects."
}

variable "sentry_team" {
  type        = string
  default     = null
  description = "Slug of the Sentry team that owns the projects. Required with sentry_organization."
}
