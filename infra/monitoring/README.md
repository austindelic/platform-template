# monitoring

Production monitoring for this app on Better Stack and Sentry, applied by a person (state key `platform-starter/monitoring.tfstate`, same encrypted R2 bucket and passphrase as the other roots). CI runs only the offline checks.

| Resource                                                                  | Name                          | Starts                               |
| ------------------------------------------------------------------------- | ----------------------------- | ------------------------------------ |
| Monitor on `<web_url>/healthz` (every 3 minutes, never follows redirects) | `<project>-prod-web`          | paused (`enable_health_monitor`)     |
| Heartbeat for the jobs Worker's sweep cron (`HEARTBEAT_URL_SWEEP`)        | `<project>-prod-sweep`        | paused (`enable_cron_heartbeat`)     |
| Backup dump, copy and restore heartbeats                                  | `<project>-prod-backup-*`     | only with `backups_enabled`          |
| Sentry projects for web and the jobs Worker, with DSN keys                | `<project>`, `<project>-jobs` | only with `sentry_organization`      |
| Status page entry                                                         | the project name              | only with `public_status` and a page |

Turn each check on only when the thing it watches is live. An Access login page answers 200, so `/healthz` needs its Access bypass (`machine_paths`) first, and the monitor is set never to follow a redirect.

Heartbeat URLs and DSNs are secrets: a leaked heartbeat lets anyone fake a healthy job. They are never printed. The `secrets` output carries them, and `infra/secrets` writes them to the Worker folders of `<app>-runtime-prod` and to `<app>-backups-prod`. Run it after each apply here. `tofu output heartbeat_secret_names` is safe to print.

```sh
export TF_VAR_state_passphrase=...                      # password manager
export BETTERUPTIME_API_TOKEN=... SENTRY_AUTH_TOKEN=...  # infra project, never files
export AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=...   # R2 state key
tofu init -backend-config=backend.hcl
tofu plan -out=tfplan && tofu apply tfplan
```

Better Stack's free plan has 10 monitors and 10 heartbeats shared across every project on the account; keep a budget if several repos share one. If a monitor already exists, adopt it with an `import` block instead of creating a second.
