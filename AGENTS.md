# Platform starter

## Architecture

- `apps/web` owns HTTP routes and presentation. Keep route files thin; put browser-safe models/components in `src/lib/features` and database workflows in `src/lib/server`. `/healthz` is a fixed `ok` for uptime monitors: no database, secrets or auth.
- `apps/worker` owns private asynchronous work. It has no public URL; the web app reaches it through the `JOBS` service binding. Keep payload contracts in `src/contracts.ts`, coordination in `src/coordinator`, and bounded processing in `src/processor`.
- `apps/docs` is the staff-facing Astro handbook. Keep its user instructions aligned with the app.
- `packages/db` owns the PostgreSQL schema, migrations, and adapter. `packages/storage` owns the S3-compatible adapter (R2 in the cloud, RustFS locally). Apps import packages, never each other's source.
- `infra/local` owns disposable local services. `infra/cloud` owns the Cloudflare resources (OpenTofu, encrypted R2 state) and the secrets model; read its README before touching cloud config. `scripts` holds operator tasks (`release.sh`). `tests` holds cross-package integration and browser tests.

## Development

Use the pinned tools from `mise.toml` and run tasks through `mise run`. Secrets come from Infisical (`.infisical.json`, ignored, env slug `main`), or from ignored `.dev.vars` files when there is no Infisical project. Never print, log, paste or commit a secret value; names only. Never copy another project's Infisical workspace ID, Cloudflare IDs or identities. Add authentication and authorization before exposing application data.

## Verification loops

Run the smallest loop that covers the change, and finish with `mise run verify` before handing work back:

| Loop     | Command                                 | Covers                                                                                                                 |
| -------- | --------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| Inner    | `mise run test`, `mise run check`       | Unit tests, types (svelte-check, tsc, astro)                                                                           |
| Pre-push | `mise run verify`                       | fmt check, types, lint, tests, build (including `wrangler deploy --dry-run`)                                           |
| Browser  | `mise run test:e2e`                     | Playwright against the local web app                                                                                   |
| Infra    | `mise run infra:check`                  | `tofu fmt`, `validate` and mocked `tofu test`, offline                                                                 |
| CI       | `checks.yml`, `infra.yml` on Blacksmith | The pre-push and browser loops, then the infra loop                                                                    |
| Release  | `deploy.yml` → `scripts/release.sh`     | Staging on merge to `main`, production on a `v*` tag; fails on leftover `REPLACE_WITH_` values or a failing `/healthz` |

When CI fails, reproduce it locally with the same `mise run` task before changing code. Do not skip, disable or loosen a check to get green.

## Extension pattern

For each feature, add a browser-safe model/component under `apps/web/src/lib/features/<feature>`, server operations under `apps/web/src/lib/server/<feature>`, thin routes under `apps/web/src/routes`, schema changes in `packages/db`, and colocated tests. Add a worker contract and processor only when the feature needs background work. A new Cloudflare binding goes in the top level and in both `env` blocks of `wrangler.jsonc` (Wrangler does not inherit them), and its resource goes in `infra/cloud/modules/workspace`.
