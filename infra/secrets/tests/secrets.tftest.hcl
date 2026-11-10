# Offline: Infisical is mocked and the three source states are overridden with fake outputs (names and dummy
# values only), so this never reads R2 or writes Infisical.
mock_provider "infisical" {}

variables {
  state_passphrase = "test-passphrase-not-a-secret"
  state_bucket     = "test-state"
  state_endpoint   = "https://0123456789abcdef0123456789abcdef.r2.cloudflarestorage.com"
  infisical_project_ids = {
    runtime_staging = "00000000-0000-0000-0000-000000000001"
    runtime_prod    = "00000000-0000-0000-0000-000000000002"
    deploy_staging  = "00000000-0000-0000-0000-000000000003"
    deploy_prod     = "00000000-0000-0000-0000-000000000004"
    backups_prod    = "00000000-0000-0000-0000-000000000005"
  }
  runtime_folders = ["web", "worker", "studio"]
}

override_data {
  target = data.terraform_remote_state.staging
  values = {
    outputs = {
      secret_names = {
        "runtime/web"    = ["BETTER_AUTH_SECRET", "STORAGE_ACCESS_KEY"]
        "runtime/worker" = ["PROCESSOR_SECRET"]
        "runtime/studio" = ["MEDIA_LINK_SECRET"]
        deploy           = ["CLOUDFLARE_API_TOKEN"]
        backups          = []
      }
      secrets = {
        "runtime/web"    = { BETTER_AUTH_SECRET = "fake-1", STORAGE_ACCESS_KEY = "fake-2" }
        "runtime/worker" = { PROCESSOR_SECRET = "fake-3" }
        "runtime/studio" = { MEDIA_LINK_SECRET = "fake-4" }
        deploy           = { CLOUDFLARE_API_TOKEN = "fake-5" }
        backups          = {}
      }
      planetscale_branch = null
    }
  }
}

override_data {
  target = data.terraform_remote_state.production
  values = {
    outputs = {
      secret_names = {
        "runtime/web" = ["BETTER_AUTH_SECRET"]
        deploy        = ["CLOUDFLARE_API_TOKEN", "DATABASE_URL_DIRECT"]
        backups       = ["BACKUP_B2_KEY_ID", "DATABASE_URL_DIRECT"]
      }
      secrets = {
        "runtime/web" = { BETTER_AUTH_SECRET = "fake-6" }
        deploy        = { CLOUDFLARE_API_TOKEN = "fake-7", DATABASE_URL_DIRECT = "fake-13" }
        backups       = { BACKUP_B2_KEY_ID = "fake-8", DATABASE_URL_DIRECT = "fake-9" }
      }
      planetscale_branch = "example/app/main"
    }
  }
}

override_data {
  target = data.terraform_remote_state.monitoring
  values = {
    outputs = {
      secret_names = {
        "runtime/worker" = ["COORDINATOR_HEARTBEAT_URL", "SENTRY_DSN"]
        backups          = ["BACKUP_HEARTBEAT_URL_DUMP"]
      }
      secrets = {
        "runtime/worker" = { COORDINATOR_HEARTBEAT_URL = "fake-10", SENTRY_DSN = "fake-11" }
        backups          = { BACKUP_HEARTBEAT_URL_DUMP = "fake-12" }
      }
    }
  }
}

run "each_secret_lands_in_its_own_project_and_folder" {
  command = plan

  assert {
    condition = (
      infisical_secret.this["staging/runtime/web/BETTER_AUTH_SECRET"].workspace_id == var.infisical_project_ids.runtime_staging &&
      infisical_secret.this["production/runtime/web/BETTER_AUTH_SECRET"].workspace_id == var.infisical_project_ids.runtime_prod
    )
    error_message = "Staging and production runtime secrets go to their own projects."
  }
  assert {
    condition = (
      infisical_secret.this["staging/deploy/CLOUDFLARE_API_TOKEN"].workspace_id == var.infisical_project_ids.deploy_staging &&
      infisical_secret.this["production/deploy/CLOUDFLARE_API_TOKEN"].workspace_id == var.infisical_project_ids.deploy_prod &&
      infisical_secret.this["staging/deploy/CLOUDFLARE_API_TOKEN"].folder_path == "/"
    )
    error_message = "Each deploy token goes to its own environment's deploy project, at the root."
  }
  assert {
    condition = alltrue([for k in ["production/backups/DATABASE_URL_DIRECT", "production/backups/BACKUP_B2_KEY_ID", "monitoring/backups/BACKUP_HEARTBEAT_URL_DUMP"] :
      infisical_secret.this[k].workspace_id == var.infisical_project_ids.backups_prod
    ])
    error_message = "Backup keys, the read-only database URL and the backup heartbeats go to <app>-backups-prod."
  }
  assert {
    condition = (
      infisical_secret.this["monitoring/runtime/worker/SENTRY_DSN"].workspace_id == var.infisical_project_ids.runtime_prod &&
      length(infisical_secret_folder.runtime) == 6 &&
      alltrue([for s in infisical_secret.this : s.env_slug == "main"])
    )
    error_message = "Monitoring values go to production's runtime folders; every project has one environment, main."
  }
  assert {
    condition     = length(output.secret_names) == 13
    error_message = "Every named secret from the three sources is written once."
  }
}

run "staging_cannot_share_productions_branch" {
  command = plan

  override_data {
    target = data.terraform_remote_state.staging
    values = {
      outputs = {
        secret_names       = { deploy = ["CLOUDFLARE_API_TOKEN"] }
        secrets            = { deploy = { CLOUDFLARE_API_TOKEN = "fake" } }
        planetscale_branch = "example/app/main"
      }
    }
  }
  expect_failures = [terraform_data.guards]
}

run "staging_has_no_backups_project" {
  command = plan

  override_data {
    target = data.terraform_remote_state.staging
    values = {
      outputs = {
        secret_names = { backups = ["BACKUP_R2_ACCESS_KEY_ID"] }
        secrets      = { backups = { BACKUP_R2_ACCESS_KEY_ID = "fake" } }
      }
    }
  }
  expect_failures = [terraform_data.guards]
}

run "unapplied_roots_write_nothing" {
  command = plan

  override_data {
    target = data.terraform_remote_state.staging
    values = { outputs = {} }
  }
  override_data {
    target = data.terraform_remote_state.production
    values = { outputs = { secret_names = null, secrets = null } }
  }
  override_data {
    target = data.terraform_remote_state.monitoring
    values = { outputs = {} }
  }
  assert {
    condition     = length(infisical_secret.this) == 0
    error_message = "A root that has not minted anything yet contributes no secrets."
  }
}

run "project_ids_must_be_distinct" {
  command = plan
  variables {
    infisical_project_ids = {
      runtime_staging = "00000000-0000-0000-0000-000000000001"
      runtime_prod    = "00000000-0000-0000-0000-000000000001"
      deploy_staging  = "00000000-0000-0000-0000-000000000003"
      deploy_prod     = "00000000-0000-0000-0000-000000000004"
      backups_prod    = "00000000-0000-0000-0000-000000000005"
    }
  }
  expect_failures = [var.infisical_project_ids]
}

run "given_outputs_stand_in_for_a_state" {
  command = plan

  variables {
    given_output_sources = ["staging"]
    given_outputs = {
      staging = {
        secret_names       = { "runtime/web" = [], "runtime/worker" = [], "runtime/studio" = [], deploy = ["CLOUDFLARE_API_TOKEN"], backups = [] }
        secrets            = { "runtime/web" = {}, "runtime/worker" = {}, "runtime/studio" = {}, deploy = { CLOUDFLARE_API_TOKEN = "given-token" }, backups = {} }
        planetscale_branch = null
      }
    }
  }

  assert {
    condition     = length(data.terraform_remote_state.staging) == 0 && length(data.terraform_remote_state.production) == 1
    error_message = "A given source is not read from its state; the others still are."
  }

  assert {
    condition     = infisical_secret.this["staging/deploy/CLOUDFLARE_API_TOKEN"].workspace_id == var.infisical_project_ids.deploy_staging && !contains(keys(infisical_secret.this), "staging/runtime/web/BETTER_AUTH_SECRET")
    error_message = "The given staging outputs, not the stand-in state, decide what is written."
  }
}

run "production_migration_url_goes_to_its_deploy_project" {
  command = plan
  assert {
    condition = (
      infisical_secret.this["production/deploy/DATABASE_URL_DIRECT"].workspace_id == var.infisical_project_ids.deploy_prod &&
      infisical_secret.this["production/deploy/DATABASE_URL_DIRECT"].folder_path == "/" &&
      infisical_secret.this["production/backups/DATABASE_URL_DIRECT"].workspace_id == var.infisical_project_ids.backups_prod
    )
    error_message = "The migration URL goes to <app>-deploy-prod at the root, where release.sh reads it; the read-only URL stays in backups."
  }
  assert {
    condition     = !contains(output.secret_names, "staging/deploy/DATABASE_URL_DIRECT")
    error_message = "Staging on the shared branch mints no migration role, so its hand-made login is left alone."
  }
}

run "migration_url_needs_a_named_branch" {
  command = plan

  override_data {
    target = data.terraform_remote_state.staging
    values = {
      outputs = {
        secret_names       = { deploy = ["CLOUDFLARE_API_TOKEN", "DATABASE_URL_DIRECT"] }
        secrets            = { deploy = { CLOUDFLARE_API_TOKEN = "fake-5", DATABASE_URL_DIRECT = "fake-14" } }
        planetscale_branch = null
      }
    }
  }

  expect_failures = [terraform_data.guards]
}

run "without_a_backups_project_backups_secrets_are_refused" {
  command = plan
  variables {
    infisical_project_ids = {
      runtime_staging = "00000000-0000-0000-0000-000000000001"
      runtime_prod    = "00000000-0000-0000-0000-000000000002"
      deploy_staging  = "00000000-0000-0000-0000-000000000003"
      deploy_prod     = "00000000-0000-0000-0000-000000000004"
    }
  }
  expect_failures = [terraform_data.guards]
}
