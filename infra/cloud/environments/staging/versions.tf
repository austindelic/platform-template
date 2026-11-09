terraform {
  required_version = "~> 1.11.5"

  # State in a private R2 bucket. Bucket, key and endpoint come from the ignored backend.hcl
  # (copy backend.hcl.example); the R2 S3 credentials come from AWS_ACCESS_KEY_ID and
  # AWS_SECRET_ACCESS_KEY (the humans-only infra Infisical project).
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

  # State holds the Hyperdrive password and service-token secrets, so it is encrypted before it
  # leaves the machine. TF_VAR_state_passphrase comes from the password manager, never Infisical.
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
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "= 5.28.1"
    }
  }
}

provider "cloudflare" {} # Reads CLOUDFLARE_API_TOKEN from the environment.
