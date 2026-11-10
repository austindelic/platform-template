terraform {
  required_version = "~> 1.11.5"

  # State in the private R2 state bucket, key platform-starter/monitoring.tfstate. Bucket, key and endpoint come from
  # the ignored backend.hcl (see backend.hcl.example); the R2 S3 credentials come from
  # AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY.
  backend "s3" {
    region                      = "auto"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
    use_path_style              = true
    use_lockfile                = true
  }

  # State holds heartbeat URLs and Sentry DSNs, so it is encrypted before it leaves the machine.
  # TF_VAR_state_passphrase comes from the password manager, never Infisical. Use the same one as the other roots so
  # infra/secrets can read this state.
  encryption {
    key_provider "pbkdf2" "state" {
      passphrase = var.state_passphrase
    }
    method "aes_gcm" "state" {
      keys = key_provider.pbkdf2.state
    }
    state {
      method   = method.aes_gcm.state
      enforced = true
    }
    plan {
      method   = method.aes_gcm.state
      enforced = true
    }
  }

  required_providers {
    betteruptime = {
      source  = "BetterStackHQ/better-uptime"
      version = "~> 0.22.4"
    }
    sentry = {
      source  = "jianyuan/sentry"
      version = "~> 0.15.8"
    }
  }
}

# Credentials come from the environment, never from files:
#   BETTERUPTIME_API_TOKEN and SENTRY_AUTH_TOKEN.
provider "betteruptime" {
  # Null falls back to BETTERUPTIME_API_TOKEN. The variable exists so offline tests can supply a dummy.
  api_token = var.betteruptime_api_token
}
provider "sentry" {}
