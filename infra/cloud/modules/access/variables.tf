variable "account_id" {
  type        = string
  description = "Cloudflare account that owns the Zero Trust organization."
  validation {
    condition     = can(regex("^[a-f0-9]{32}$", var.account_id))
    error_message = "account_id must be a 32-character Cloudflare account ID."
  }
}

variable "name" {
  type        = string
  description = "Application name shown in Access and the App Launcher, for example \"Platform starter (staging)\"."
}

variable "hostname" {
  type        = string
  description = "Hostname of the application, without scheme or path. Protected as a whole unless staff_paths is set."
  validation {
    condition     = can(regex("^([a-z0-9]([a-z0-9-]*[a-z0-9])?\\.)+[a-z]{2,}$", var.hostname))
    error_message = "Use a hostname without a scheme or path."
  }
}

variable "extra_hostnames" {
  type        = list(string)
  default     = []
  description = "More hostnames the staff application covers as a whole, such as a second domain for the same app. Not with staff_paths."
  validation {
    condition     = alltrue([for h in var.extra_hostnames : can(regex("^(\\*\\.)?([a-z0-9]([a-z0-9-]*[a-z0-9])?\\.)+[a-z]{2,}$", h))])
    error_message = "Use hostnames without a scheme or path; a leading \"*.\" is allowed."
  }
}

variable "staff_paths" {
  type        = list(string)
  default     = null
  description = "Paths the staff application covers, each with its subpaths, for example [\"staff\"]. Null covers the whole host; with paths, everything else on the host is public."
  validation {
    condition     = var.staff_paths == null || length(coalesce(var.staff_paths, [])) > 0
    error_message = "List at least one staff path, or leave staff_paths null to cover the whole host."
  }
  validation {
    condition     = alltrue([for p in coalesce(var.staff_paths, []) : can(regex("^[a-z0-9][a-z0-9._/-]*[a-z0-9]$", p))])
    error_message = "Write staff paths without a leading slash or wildcard, for example \"staff\"."
  }
}

variable "identity_provider_id" {
  type        = string
  description = "ID of the Access Google identity provider. Staff sign in only through it; the policy admits only the allowed email domains."
  validation {
    condition     = length(trimspace(var.identity_provider_id)) > 0
    error_message = "identity_provider_id must be the Google identity provider's ID."
  }
}

variable "allowed_email_domains" {
  type        = list(string)
  description = "Email domains allowed into the staff UI, for example [\"example.com\"]. The identity provider must also be used (a require rule)."
  validation {
    condition     = length(var.allowed_email_domains) > 0
    error_message = "Allow at least one email domain."
  }
}

variable "allowed_emails" {
  type        = list(string)
  default     = []
  description = "Individual addresses allowed in addition to the domains. They must still sign in through the identity provider."
}

variable "session_duration" {
  type        = string
  default     = "24h"
  description = "How long a staff Access session lasts before signing in again."
}

variable "machine_paths" {
  type = list(object({
    path = string
    mode = string
  }))
  default     = []
  description = <<-EOT
    Paths under the hostname that machines call without a browser sign-in. Each path covers its subpaths.
    mode "service_token": only this application's service tokens get through (CF-Access-Client-Id/Secret headers).
    mode "bypass": Access does not check the request; the app must authenticate it itself (bearer keys, signed URLs).
  EOT
  validation {
    condition     = alltrue([for p in var.machine_paths : contains(["service_token", "bypass"], p.mode)])
    error_message = "Each machine path mode must be \"service_token\" or \"bypass\"."
  }
  validation {
    condition     = alltrue([for p in var.machine_paths : can(regex("^[a-z0-9][a-z0-9._/-]*[a-z0-9]$", p.path))])
    error_message = "Write machine paths without a leading slash or wildcard, for example \"api/v1\"."
  }
  validation {
    condition     = length(distinct([for p in var.machine_paths : p.path])) == length(var.machine_paths)
    error_message = "List each machine path once."
  }
}

variable "service_tokens" {
  type        = map(object({ duration = optional(string, "8760h") }))
  default     = {}
  description = "Service tokens for this application only, one per caller pool (for example \"claude-code-cloud\"). Keys become token names."
}

variable "machine_oauth" {
  type = object({
    redirect_uris         = list(string)
    allow_loopback        = optional(bool, true)
    access_token_lifetime = optional(string, "15m")
    session_duration      = optional(string, "336h")
  })
  default     = null
  description = <<-EOT
    Managed OAuth on the service_token paths' application, for MCP clients that cannot send headers
    (claude.ai connectors). Access becomes the OAuth server, admits staff through the same policy as the
    browser, and registers clients dynamically only for these https redirect URIs (plus localhost and
    loopback when allow_loopback, for Claude Code). Null keeps those paths service-token only.
  EOT
  validation {
    condition     = var.machine_oauth == null || alltrue([for u in try(var.machine_oauth.redirect_uris, []) : startswith(u, "https://")])
    error_message = "OAuth redirect URIs must use https."
  }
}
