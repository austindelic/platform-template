# Production monitoring: one /healthz monitor, a heartbeat per scheduled job, and Sentry projects for
# the Workers. Names follow <project>-<env>-<job>. Applied by a person; CI only runs offline checks.
# Better Stack's free plan has 10 monitors and 10 heartbeats shared across every project on the
# account, so add entries sparingly.

locals {
  environment = "prod"

  monitors = {
    web = {
      name          = "${var.project}-${local.environment}-web"
      url           = "${var.web_url}/healthz"
      public_name   = var.project
      public_status = var.public_status
      paused        = !var.enable_health_monitor
    }
  }

  # A job pings its URL when it finishes, and <url>/fail on failure; a missed ping past the grace opens an incident.
  # `dest` is where infra/secrets writes the URL: a Worker folder of <app>-runtime-prod, or the backups project.
  heartbeats = merge(
    {
      sweep = {
        name   = "${var.project}-${local.environment}-sweep"
        period = 900 # apps/worker SCHEDULES: */15
        grace  = 600
        secret = "HEARTBEAT_URL_SWEEP"
        dest   = "runtime/worker"
        paused = !var.enable_cron_heartbeat
      }
    },
    var.backups_enabled ? {
      backup-dump = {
        name   = "${var.project}-${local.environment}-backup-dump"
        period = 86400
        grace  = 10800
        secret = "BACKUP_HEARTBEAT_URL_DUMP"
        dest   = "backups"
        paused = false
      }
      backup-copy = {
        name   = "${var.project}-${local.environment}-backup-copy"
        period = 86400
        grace  = 10800
        secret = "BACKUP_HEARTBEAT_URL_COPY"
        dest   = "backups"
        paused = false
      }
      backup-restore = {
        name   = "${var.project}-${local.environment}-backup-restore"
        period = 604800
        grace  = 21600
        secret = "BACKUP_HEARTBEAT_URL_RESTORE"
        dest   = "backups"
        paused = false
      }
    } : {},
  )

  sentry_projects = var.sentry_organization == null ? {} : {
    (var.project)         = { name = var.project, platform = "node-cloudflare-workers", folder = "web" }
    "${var.project}-jobs" = { name = "${var.project} jobs", platform = "node-cloudflare-workers", folder = "worker" }
  }

  # Empty without a page, so the guard below reports the missing IDs instead of the provider.
  public_monitors = var.status_page_id == null || var.status_page_section_id == null ? {} : {
    for k, m in local.monitors : k => m if m.public_status
  }
}

resource "terraform_data" "guards" {
  lifecycle {
    precondition {
      condition     = !var.public_status || (var.status_page_id != null && var.status_page_section_id != null)
      error_message = "public_status needs status_page_id and status_page_section_id."
    }
    precondition {
      condition     = var.sentry_organization == null || var.sentry_team != null
      error_message = "sentry_organization needs sentry_team."
    }
  }
}

resource "betteruptime_monitor" "http" {
  for_each = local.monitors

  url                = each.value.url
  monitor_type       = "status"
  pronounceable_name = each.value.name
  check_frequency    = 180 # The free plan checks every 3 minutes.
  ssl_expiration     = 14
  # A redirect means Cloudflare Access answered instead of the app: an Access login page returns
  # 200, so following it would report a dead app as healthy.
  follow_redirects = false
  paused           = each.value.paused
}

resource "betteruptime_heartbeat" "job" {
  for_each = local.heartbeats

  name   = each.value.name
  period = each.value.period
  grace  = each.value.grace
  paused = each.value.paused
}

resource "betteruptime_status_page_resource" "public" {
  for_each = local.public_monitors

  status_page_id         = var.status_page_id
  status_page_section_id = var.status_page_section_id
  resource_id            = betteruptime_monitor.http[each.key].id
  resource_type          = "Monitor"
  public_name            = each.value.public_name
}

resource "sentry_project" "app" {
  for_each = local.sentry_projects

  organization  = var.sentry_organization
  teams         = [var.sentry_team]
  name          = each.value.name
  slug          = each.key
  platform      = each.value.platform
  default_rules = true # Email on every new issue.
}

resource "sentry_key" "app" {
  for_each = local.sentry_projects

  organization = var.sentry_organization
  project      = sentry_project.app[each.key].slug
  name         = "default"
}
