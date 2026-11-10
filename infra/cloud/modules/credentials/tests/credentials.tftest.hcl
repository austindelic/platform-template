# Offline: every provider is mocked.
mock_provider "cloudflare" {
  mock_data "cloudflare_account_api_token_permission_groups_list" {
    defaults = {
      result = [
        { id = "g-scripts-zone", name = "Workers Scripts Write", category = "Account", is_selectable = true, scopes = ["com.cloudflare.api.account.zone"] },
        { id = "g-scripts", name = "Workers Scripts Write", category = "Account", is_selectable = true, scopes = ["com.cloudflare.api.account"] },
        { id = "g-r2-write", name = "Workers R2 Storage Write", category = "Account", is_selectable = true, scopes = ["com.cloudflare.api.account"] },
        { id = "g-hyperdrive", name = "Hyperdrive Write", category = "Account", is_selectable = true, scopes = ["com.cloudflare.api.account"] },
        { id = "g-settings", name = "Account Settings Read", category = "Account", is_selectable = true, scopes = ["com.cloudflare.api.account"] },
        { id = "g-queues", name = "Queues Write", category = "Account", is_selectable = true, scopes = ["com.cloudflare.api.account"] },
        { id = "g-item-write", name = "Workers R2 Storage Bucket Item Write", category = "Account", is_selectable = true, scopes = ["com.cloudflare.edge.r2.bucket"] },
        { id = "g-item-read", name = "Workers R2 Storage Bucket Item Read", category = "Account", is_selectable = true, scopes = ["com.cloudflare.edge.r2.bucket"] },
      ]
    }
  }
}
mock_provider "planetscale" {
  mock_resource "planetscale_postgres_branch_role" {
    defaults = { username = "mock-role.branchid", password = "mock-password", access_host_url = "mock.pg.psdb.cloud" }
  }
}
mock_provider "b2" {
  mock_data "b2_bucket" {
    defaults = { bucket_id = "mock-bucket-id" }
  }
}
mock_provider "random" {}
mock_provider "time" {
  mock_resource "time_rotating" {
    defaults = { rfc3339 = "2026-11-04T00:00:00Z", rotation_rfc3339 = "2027-02-02T00:00:00Z" }
  }
}

variables {
  account_id          = "0123456789abcdef0123456789abcdef"
  project             = "platform-starter"
  environment         = "staging"
  storage_bucket_name = "platform-starter-staging"
}

run "staging_without_backups_or_roles" {
  command = plan
  assert {
    condition     = toset([for g in cloudflare_account_token.deploy.policies[0].permission_groups : g.id]) == toset(["g-scripts", "g-r2-write", "g-hyperdrive", "g-settings"])
    error_message = "The deploy token has only what wrangler deploy needs by default."
  }
  assert {
    condition     = startswith(cloudflare_account_token.deploy.name, "platform-starter deploy staging (replace by 2027-02-02)")
    error_message = "Token names carry the project, environment and replace-by date."
  }
  assert {
    condition     = contains([for g in cloudflare_account_token.deploy.policies[0].permission_groups : g.id], "g-scripts") && !contains([for g in cloudflare_account_token.deploy.policies[0].permission_groups : g.id], "g-scripts-zone")
    error_message = "A name listed for both scopes resolves to the account-scoped group."
  }
  assert {
    condition     = length(cloudflare_account_token.backups) == 0 && length(b2_application_key.copy) == 0
    error_message = "No backups token or B2 key without a backups bucket."
  }
  assert {
    condition     = strcontains(cloudflare_account_token.storage.policies[0].resources, "platform-starter-staging") && !strcontains(cloudflare_account_token.storage.policies[0].resources, "\"*\":\"*\"")
    error_message = "The app's R2 key covers its own bucket only."
  }
  assert {
    condition     = output.secret_names["runtime/web"] == tolist(["STORAGE_ACCESS_KEY", "STORAGE_SECRET_KEY"]) && output.secret_names["runtime/worker"] == tolist(["STORAGE_ACCESS_KEY", "STORAGE_SECRET_KEY"])
    error_message = "Both Workers get the bucket-scoped R2 key by default, and nothing else."
  }
  assert {
    condition     = output.secret_names.deploy == tolist(["CLOUDFLARE_ACCOUNT_ID", "CLOUDFLARE_API_TOKEN"]) && length(output.secret_names.backups) == 0
    error_message = "Deploy holds the token and account ID; staging has no backups."
  }
  assert {
    condition     = output.hyperdrive_username == null && length(planetscale_postgres_branch_role.app) == 0
    error_message = "No PlanetScale database, no roles."
  }
}

run "staging_on_a_shared_branch_mints_no_roles" {
  command = plan
  variables {
    planetscale = { organization = "example", database = "app", database_name = "app_staging" }
  }
  assert {
    condition     = length(planetscale_postgres_branch_role.app) == 0 && output.hyperdrive_username == null
    error_message = "Staging gets no cluster-wide role while it shares production's branch."
  }
  assert {
    condition     = length(planetscale_postgres_branch_role.migrate) == 0 && !contains(output.secret_names.deploy, "DATABASE_URL_DIRECT") && output.expires.migration_role_expires == null
    error_message = "No migration role on the shared branch: it would inherit postgres and reach production, so staging keeps its own login."
  }
}

run "staging_on_its_own_branch_mints_the_hyperdrive_role" {
  command = plan
  variables {
    planetscale = { organization = "example", database = "app", branch = "staging", database_name = "app_staging", dedicated_branch = true }
  }
  assert {
    condition     = length(planetscale_postgres_branch_role.app) == 1 && length(planetscale_postgres_branch_role.backups) == 0
    error_message = "A dedicated staging branch gets the Hyperdrive role, and still no backups role."
  }
  assert {
    condition     = length(planetscale_postgres_branch_role.migrate) == 1 && strcontains(output.secrets.deploy.DATABASE_URL_DIRECT, "/app_staging?")
    error_message = "A dedicated staging branch gets its own migration role, on its own database."
  }
}

run "production_mints_everything" {
  command = plan
  variables {
    environment         = "production"
    storage_bucket_name = "platform-starter-production"
    backups_bucket_name = "platform-starter-backups-production"
    b2_bucket_name      = "example-backups"
    planetscale         = { organization = "example", database = "app", database_name = "app" }
  }
  assert {
    condition     = tolist(planetscale_postgres_branch_role.backups[0].inherited_roles) == tolist(["pg_read_all_data"]) && planetscale_postgres_branch_role.backups[0].ttl == (60 + 14) * 86400
    error_message = "The backups role is read-only and expires by itself."
  }
  assert {
    condition     = !contains(tolist(planetscale_postgres_branch_role.app[0].inherited_roles), "postgres")
    error_message = "The Hyperdrive role is never the admin."
  }
  assert {
    condition     = !contains(tolist(b2_application_key.copy[0].capabilities), "deleteFiles") && b2_application_key.copy[0].bucket_id == "mock-bucket-id" && b2_application_key.copy[0].valid_duration_in_seconds == (90 + 14) * 86400
    error_message = "The B2 key is limited to the copy bucket, cannot delete and expires."
  }
  assert {
    condition     = output.secret_names.backups == tolist(["BACKUP_B2_APPLICATION_KEY", "BACKUP_B2_BUCKET", "BACKUP_B2_KEY_ID", "BACKUP_R2_ACCESS_KEY_ID", "BACKUP_R2_ENDPOINT", "BACKUP_R2_SECRET_ACCESS_KEY", "DATABASE_URL_DIRECT"])
    error_message = "Backups get the R2 and B2 keys and the read-only database URL."
  }
}

run "production_migration_role_is_short_lived_and_deploy_only" {
  command = plan
  variables {
    environment         = "production"
    storage_bucket_name = "platform-starter-production"
    backups_bucket_name = "platform-starter-backups-production"
    planetscale         = { organization = "example", database = "app", database_name = "app" }
  }
  assert {
    condition     = toset(planetscale_postgres_branch_role.migrate[0].inherited_roles) == toset(["postgres"]) && planetscale_postgres_branch_role.migrate[0].ttl == 7 * 86400 && planetscale_postgres_branch_role.migrate[0].successor == "postgres"
    error_message = "The migration role has DDL (inherits postgres), expires after 7 days and hands what it owns to postgres."
  }
  assert {
    condition     = planetscale_postgres_branch_role.migrate[0].name == "platform-starter-production-migrate-20261104" && time_rotating.migration[0].rotation_days == 7
    error_message = "The migration role is named by the day it was minted and replaced by the first apply after it lapses."
  }
  assert {
    condition     = output.secret_names.deploy == tolist(["CLOUDFLARE_ACCOUNT_ID", "CLOUDFLARE_API_TOKEN", "DATABASE_URL_DIRECT"])
    error_message = "The deploy project gets the migration URL as DATABASE_URL_DIRECT, the name release.sh reads."
  }
  assert {
    condition = (
      startswith(output.secrets.deploy.DATABASE_URL_DIRECT, "postgresql://mock-role.branchid:mock-password@mock.pg.psdb.cloud:5432/app?") &&
      strcontains(output.secrets.deploy.DATABASE_URL_DIRECT, "sslmode=verify-full") &&
      strcontains(output.secrets.deploy.DATABASE_URL_DIRECT, "options=-c%20role%3Dpostgres")
    )
    error_message = "The migration URL reaches the production database over TLS, and its sessions act as postgres so new objects outlive the dated role."
  }
  assert {
    condition     = output.secrets.deploy.DATABASE_URL_DIRECT != output.secrets.backups.DATABASE_URL_DIRECT && planetscale_postgres_branch_role.migrate[0].name != planetscale_postgres_branch_role.backups[0].name && planetscale_postgres_branch_role.migrate[0].name != planetscale_postgres_branch_role.app[0].name
    error_message = "Migrations never share a role with Hyperdrive or the backups."
  }
  assert {
    condition     = output.expires.migration_role_expires == "2027-02-02T00:00:00Z"
    error_message = "credentials_expire says when the migration role lapses."
  }
}

run "rejects_a_long_lived_migration_role" {
  command = plan
  variables {
    migration_role_ttl_days = 90
  }
  expect_failures = [var.migration_role_ttl_days]
}

run "rotation_bounds" {
  command = plan
  variables {
    rotation_days = { tokens = 1 }
  }
  expect_failures = [var.rotation_days]
}

run "b2_key_cannot_delete" {
  command = plan
  variables {
    b2_capabilities = ["listFiles", "writeFiles", "deleteFiles"]
  }
  expect_failures = [var.b2_capabilities]
}

run "app_secrets_go_only_to_their_folders" {
  command = plan
  variables {
    app_secrets              = { SESSION_SECRET = ["web"], SHARED_SECRET = ["web", "worker"], MCP_SECRET = ["mcp"] }
    deploy_permission_groups = ["Workers Scripts Write", "Queues Write"]
  }
  assert {
    condition     = output.secret_names["runtime/web"] == tolist(["SESSION_SECRET", "SHARED_SECRET", "STORAGE_ACCESS_KEY", "STORAGE_SECRET_KEY"])
    error_message = "The web folder gets its secrets and the R2 key."
  }
  assert {
    condition     = output.secret_names["runtime/worker"] == tolist(["SHARED_SECRET", "STORAGE_ACCESS_KEY", "STORAGE_SECRET_KEY"]) && output.secret_names["runtime/mcp"] == tolist(["MCP_SECRET"])
    error_message = "A secret reaches only the folders listed for it; a new folder needs no storage key."
  }
  assert {
    condition     = contains([for g in cloudflare_account_token.deploy.policies[0].permission_groups : g.id], "g-queues")
    error_message = "Extra deploy permissions pass through."
  }
}

run "rejects_lower_case_secret_names" {
  command = plan
  variables {
    app_secrets = { session_secret = ["web"] }
  }
  expect_failures = [var.app_secrets]
}
