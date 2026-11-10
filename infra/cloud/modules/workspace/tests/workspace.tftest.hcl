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

run "backups_bucket_is_locked_and_expires_after_the_lock" {
  command = plan
  variables {
    environment = "production"
    backups     = {}
  }
  assert {
    condition     = cloudflare_r2_bucket.backups[0].name == "platform-starter-backups-production"
    error_message = "The backups bucket is <project>-backups-<environment>."
  }
  assert {
    condition     = cloudflare_r2_bucket_lock.backups[0].rules[0].condition.max_age_seconds == 30 * 86400 && cloudflare_r2_bucket_lifecycle.backups[0].rules[1].delete_objects_transition.condition.max_age == 31 * 86400
    error_message = "Daily dumps are locked 30 days and expire a day later."
  }
}

run "no_backups_bucket_by_default" {
  command = plan
  assert {
    condition     = length(cloudflare_r2_bucket.backups) == 0 && output.backups_bucket == null
    error_message = "Backups are opt-in."
  }
}

run "expiry_must_outlast_the_lock" {
  command = plan
  variables {
    backups = { daily_lock_days = 30, daily_keep_days = 7 }
  }
  expect_failures = [var.backups]
}

run "each_queue_has_a_dead_letter_queue" {
  command = plan
  variables {
    queues = ["jobs"]
  }
  assert {
    condition     = cloudflare_queue.job["jobs"].queue_name == "platform-starter-jobs-staging" && cloudflare_queue.dead_letter["jobs"].queue_name == "platform-starter-jobs-dlq-staging"
    error_message = "Queues are <project>-<key>-<env> with a -dlq- twin."
  }
}
