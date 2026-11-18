# Platform starter

A starter for internal web apps on Cloudflare. It has the workspace layout, local and cloud loops, CI and secrets handling already wired up, and no product code, credentials or account IDs. The stack:

- SvelteKit web app and a private jobs Worker (Durable Objects) on Cloudflare Workers, plus an Astro handbook
- PostgreSQL through Drizzle and Hyperdrive, and R2 object storage
- OpenTofu for Cloudflare resources, with encrypted state in R2
- Infisical for secrets, read by CI over GitHub OIDC
- GitHub Actions on GitHub-hosted runners, or Blacksmith runners for org repos
- Pinned tools through mise

<!-- template-only:start -->

## Create your project

1. Click **Use this template** on GitHub and clone your new repo, or clone this one. Install mise, then run `mise trust && mise install` and `mise exec -- bun install`.
2. Rename it and move its local ports so it can run beside other projects:

   ```bash
   mise exec -- bun scripts/create-repo.ts --slug acme-portal --in-place --dry-run
   ```

   Check the ports it prints, then run it again without `--dry-run`. Pass `--runner blacksmith` if your org runs CI on Blacksmith. It renames the identifiers listed in `template.json` (package names, database and bucket names, titles), shifts the six local ports to a free range, and records the template commit in `.template-origin.json`. It never pushes or touches cloud accounts. Review the result with `git diff` and commit it. To copy a checkout of the template into a new folder instead, pass `--dest ../acme-portal` in place of `--in-place`. Run it with `--help` for the other options.

3. Put your own people or teams in `.github/CODEOWNERS`.

The script removes this section, `template.json`, itself and the template's contributor docs from your project.

<!-- template-only:end -->

## Start locally

1. Install mise and Docker with Compose v2. Run `mise trust && mise install`.
2. Run `mise exec -- bun install`.
3. Optional: run `mise exec -- infisical login`, then `mise exec -- infisical init` and select **this project's `<app>-dev` Infisical project** (one environment, slug `main`). The generated `.infisical.json` is ignored. Without it, the apps use local defaults and any ignored `.dev.vars` files.
4. Run `mise run infra:up` (Postgres and RustFS, plus the local bucket), `mise run db:migrate`, then `mise run dev`. Open the web app at `http://127.0.0.1:5177` and the handbook at `http://127.0.0.1:4323`.

The example Items page exercises the path from a SvelteKit route to a server operation to the shared Drizzle schema. The Jobs Worker illustrates the private service binding and the processor boundary. The storage adapter is ready for a feature that needs object storage.

## Checks

`mise run verify` runs the format check, lint, types, unit tests and build. `mise run test:e2e` runs the browser tests and `mise run infra:check` runs the offline OpenTofu checks. CI runs the same tasks. [AGENTS.md](AGENTS.md) lists every loop and the code ownership rules.

## Going to the cloud

Follow [infra/cloud/README.md](infra/cloud/README.md): state bucket, OpenTofu apply, Infisical projects and OIDC identities, Wrangler environments, then the first deploy. Deploys stay off until the repository variable `DEPLOY_ENABLED` is `true`. After that, `main` deploys staging and a `v*` tag on `main` deploys production.

Each of these ships switched off; the recipes are in `infra/cloud/README.md`:

- **Key minting**: `manage_credentials`, then `infra/secrets`. Deploy tokens, R2 keys, app secrets and database roles get an expiry and a rotation schedule, and are written to Infisical without anyone handling them.
- **Monitoring**: `infra/monitoring`. A Better Stack `/healthz` monitor, cron and backup heartbeats, and Sentry.
- **Backups**: `backups_enabled` and `BACKUPS_ENABLED`. Nightly encrypted dumps to a locked R2 bucket, a copy in B2, and a weekly restore test.
- **Queues**: `queues`. A queue and a dead-letter queue per key, with a guarded consumer.

Before a real launch, add your authentication and access policy, define your domain schema and replace the example feature.

## Licence

[MIT](LICENSE). The agent skills in `.agents/skills` are adapted from Context7's `find-docs` skill and Microsoft's `playwright-cli` skill and keep their upstream licences.

<!-- template-only:start -->

See [CONTRIBUTING.md](CONTRIBUTING.md) to change the template and [SECURITY.md](SECURITY.md) to report a vulnerability.

<!-- template-only:end -->
