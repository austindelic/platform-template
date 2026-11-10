# Offline: Sentry is mocked; the Better Stack provider cannot be (its local name differs from its type), but planning
# new resources needs no network, so it runs with a dummy token.
provider "betteruptime" {
  api_token = "mock-token"
}
mock_provider "sentry" {
  mock_resource "sentry_key" {
    defaults = { dsn = { public = "https://public@o0.ingest.sentry.io/0" } }
  }
}

variables {
  state_passphrase       = "test-passphrase-not-secret-1234"
  betteruptime_api_token = "mock-token"
  web_url                = "https://app.example.com"
}

run "starts_paused_with_one_monitor_and_heartbeat" {
  command = plan
  assert {
    condition     = betteruptime_monitor.http["web"].paused && betteruptime_heartbeat.job["sweep"].paused
    error_message = "Nothing pages until it is switched on."
  }
  assert {
    condition     = length(betteruptime_monitor.http) == 1 && length(betteruptime_heartbeat.job) == 1 && length(sentry_project.app) == 0
    error_message = "One monitor, one heartbeat, no Sentry without an organisation."
  }
  assert {
    condition     = betteruptime_monitor.http["web"].url == "https://app.example.com/healthz" && betteruptime_monitor.http["web"].follow_redirects == false
    error_message = "The monitor checks /healthz and never follows a redirect to an Access login."
  }
  assert {
    condition     = keys(output.secret_names) == ["runtime/worker"] && output.secret_names["runtime/worker"] == tolist(["HEARTBEAT_URL_SWEEP"])
    error_message = "The sweep heartbeat URL goes to the jobs Worker's folder."
  }
}

run "names_follow_project_env_job" {
  command = plan
  variables {
    backups_enabled = true
  }
  assert {
    condition     = alltrue([for h in betteruptime_heartbeat.job : can(regex("^platform-starter-prod-[a-z-]+$", h.name))])
    error_message = "Heartbeat names are <project>-prod-<job>."
  }
  assert {
    condition     = output.secret_names.backups == tolist(["BACKUP_HEARTBEAT_URL_COPY", "BACKUP_HEARTBEAT_URL_DUMP", "BACKUP_HEARTBEAT_URL_RESTORE"])
    error_message = "Backup heartbeat URLs go to the backups project."
  }
}

run "sentry_projects_per_worker" {
  command = plan
  variables {
    sentry_organization = "example"
    sentry_team         = "platform"
  }
  assert {
    condition     = output.secret_names["runtime/web"] == tolist(["SENTRY_DSN"]) && output.secret_names["runtime/worker"] == tolist(["HEARTBEAT_URL_SWEEP", "SENTRY_DSN"])
    error_message = "Each Worker folder gets its own project's DSN."
  }
}

run "public_status_needs_a_page" {
  command = plan
  variables {
    public_status = true
  }
  expect_failures = [terraform_data.guards]
}

run "web_url_is_an_origin" {
  command = plan
  variables {
    web_url = "http://app.example.com/healthz"
  }
  expect_failures = [var.web_url]
}
