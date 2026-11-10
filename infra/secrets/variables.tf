variable "state_passphrase" {
  type        = string
  sensitive   = true
  description = "Encrypts this root's state and plan, and by default decrypts the states it reads. TF_VAR_state_passphrase from the password manager; never in Infisical or a tfvars file."
  validation {
    condition     = length(var.state_passphrase) >= 16
    error_message = "state_passphrase must be at least 16 characters."
  }
}

variable "given_output_sources" {
  type        = list(string)
  default     = []
  description = "Sources (staging, production, monitoring) whose outputs come from given_outputs instead of their state, because that state uses a different passphrase."
  validation {
    condition     = alltrue([for s in var.given_output_sources : contains(["staging", "production", "monitoring"], s)])
    error_message = "given_output_sources may list only staging, production and monitoring."
  }
}

variable "given_outputs" {
  type        = any
  default     = {}
  sensitive   = true
  description = "Outputs of the sources in given_output_sources, keyed by source then output name (source-outputs.sh prints this). Never in a file."
}

variable "state_bucket" {
  type        = string
  description = "The private R2 bucket that holds every OpenTofu state (the bucket in backend.hcl). An identifier, not a secret."
}

variable "state_endpoint" {
  type        = string
  description = "S3 endpoint of the state bucket, https://<account id>.r2.cloudflarestorage.com. An identifier, not a secret."
}

variable "state_keys" {
  type = object({
    staging    = optional(string, "platform-starter/staging.tfstate")
    production = optional(string, "platform-starter/production.tfstate")
    monitoring = optional(string, "platform-starter/monitoring.tfstate")
  })
  default     = {}
  description = "State keys of the roots whose `secrets` output this root writes to Infisical."
}

variable "infisical_project_ids" {
  type = object({
    runtime_staging = string
    runtime_prod    = string
    deploy_staging  = string
    deploy_prod     = string
    backups_prod    = optional(string)
  })
  description = "IDs of the <app>-<kind>-<env> Infisical projects (infra/cloud/README.md, Secrets model). Created by hand first, each with one environment, slug main; backups_prod only with backups on. Identifiers, not secrets."
  validation {
    condition     = alltrue([for id in values(var.infisical_project_ids) : id == null || can(regex("^[0-9a-f-]{36}$", id))])
    error_message = "Infisical project IDs are UUIDs."
  }
  validation {
    condition     = length(distinct(compact(values(var.infisical_project_ids)))) == length(compact(values(var.infisical_project_ids)))
    error_message = "Each kind and environment has its own project; two entries share an ID."
  }
}

variable "infisical_environment_slug" {
  type        = string
  default     = "main"
  description = "The single environment slug in every project of the split layout."
}

variable "runtime_folders" {
  type        = list(string)
  default     = ["web", "worker"]
  description = "Folders of each <app>-runtime-<env> project, one per Worker. Created here; a runtime secret for any other folder is refused."
}
