# Platform starter

A generic starter extracted from the architecture of Next Frame and the repos built on it. It keeps the same workspace boundaries without any product content, credentials or release identities. The stack:

- SvelteKit web app and a private jobs Worker (Durable Objects) on Cloudflare Workers, plus an Astro handbook
- PostgreSQL through Drizzle and Hyperdrive, and R2 object storage
- OpenTofu for Cloudflare resources, with encrypted state in R2
- Infisical for secrets, read by CI over GitHub OIDC
- GitHub Actions on Blacksmith runners
- Pinned tools through mise

New repos are made from this template with the `new-platform-repo` Claude skill, which also renames the identifiers listed in `template.json`.

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

Before a real launch, add your authentication and access policy, define your domain schema and replace the example feature.
