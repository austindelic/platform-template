mock_provider "cloudflare" {}

variables {
  account_id  = "0123456789abcdef0123456789abcdef"
  project     = "platform-starter"
  environment = "staging"
}

run "bucket_only_without_database" {
  command = plan

  assert {
    condition     = cloudflare_r2_bucket.storage.name == "platform-starter-staging"
    error_message = "The bucket is named <project>-<environment>."
  }
  assert {
    condition     = length(cloudflare_hyperdrive_config.database) == 0
    error_message = "No Hyperdrive config until a database is given."
  }
  assert {
    condition     = output.wrangler_vars.STORAGE_REGION == "auto"
    error_message = "R2 uses region auto."
  }
}

run "hyperdrive_needs_password" {
  command = plan
  variables {
    database = { host = "db.example.com", name = "app", user = "app" }
  }
  expect_failures = [cloudflare_hyperdrive_config.database]
}

run "rejects_unknown_environment" {
  command = plan
  variables {
    environment = "dev"
  }
  expect_failures = [var.environment]
}
