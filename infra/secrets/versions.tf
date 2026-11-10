terraform {
  required_version = "~> 1.11.5"

  # State in the private R2 state bucket, key platform-starter/secrets.tfstate. Bucket, key and endpoint come from
  # the ignored backend.hcl (see backend.hcl.example); the R2 S3 credentials come from AWS_ACCESS_KEY_ID /
  # AWS_SECRET_ACCESS_KEY.
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

  # This root's own state and plan, and the encrypted states it reads (infra/cloud environments and infra/monitoring),
  # with a passphrase from the password manager, never Infisical. State encryption keys each state's salt by key
  # provider name, so only states written with this passphrase under "state" can be read here; a source with its own
  # passphrase comes in through given_outputs instead (source-outputs.sh).
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
    remote_state_data_sources {
      default {
        method = method.aes_gcm.state
      }
    }
  }

  required_providers {
    infisical = {
      source  = "Infisical/infisical"
      version = "~> 0.20.10"
    }
  }
}

# The temporary tofu-secrets-tmp identity (README). Reads INFISICAL_UNIVERSAL_AUTH_CLIENT_ID and
# INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET from the environment.
provider "infisical" {}
