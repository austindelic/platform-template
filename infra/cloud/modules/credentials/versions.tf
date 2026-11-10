terraform {
  required_version = "~> 1.11.5"
  required_providers {
    b2 = {
      source  = "Backblaze/b2"
      version = "~> 0.14.1"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "= 5.28.1"
    }
    planetscale = {
      source  = "planetscale/planetscale"
      version = "~> 1.18"
    }
    random = {
      source  = "hashicorp/random"
      version = "= 3.7.2"
    }
    time = {
      source  = "hashicorp/time"
      version = "= 0.13.1"
    }
  }
}
