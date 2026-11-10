# Platform starter

## Architecture

- `apps/web` owns HTTP routes and presentation. Keep route files thin; put browser-safe models/components in `src/lib/features` and database workflows in `src/lib/server`. `hooks.server.ts` verifies the Cloudflare Access JWT on every request except `/healthz`, a fixed `ok` for uptime monitors that uses no database, secrets or auth. Get the database through `$lib/server/db` (one pool per request), never a pool per call.
- `apps/worker` owns private asynchronous work and cron (`src/schedules.ts`). It has no public URL; the web app reaches it through the `JOBS` service binding. Keep payload contracts in `src/contracts.ts`, coordination in `src/coordinator`, and bounded processing in `src/processor`.
- `apps/docs` is the staff-facing Astro handbook. Keep its user instructions aligned with the app.
- `packages/db` owns the PostgreSQL schema, migrations, and adapter. `packages/storage` owns the S3-compatible adapter (R2 in the cloud, RustFS locally). Apps import packages, never each other's source.
- `infra/local` owns disposable local services. `infra/cloud` owns the Cloudflare resources (OpenTofu, encrypted R2 state) and the secrets model; read its README before touching cloud config. `scripts` holds operator tasks (`release.sh`, `push-secrets.sh`, `hosted.sh`). `tests` holds integration, browser and config tests.

## Development

Use the pinned tools from `mise.toml` and run tasks through `mise run`. `mise run tools:setup` adds the agent tools pinned in `mise.dev.toml` (ctx7, playwright-cli, rtk, gh); run them as `mise -E dev exec -- <tool>`. The project skills in `.agents/skills` (`find-docs` for version-exact library docs, `playwright-cli` for driving the app) are pinned in `skills-lock.json`; update a skill and its hash together.

Secrets come from Infisical (`.infisical.json`, ignored, env slug `main`), or from ignored `.dev.vars` files when there is no Infisical project. Never print, log, paste or commit a secret value; names only. Never copy another project's Infisical workspace ID, Cloudflare IDs or identities. Add authentication and authorization before exposing application data.

## Rules for agents

- Agents open branches and PRs; people merge them. No agent merges, pushes to `main`, tags a release, deploys, or runs `tofu apply`, and none mints tokens or creates Infisical identities.
- Commit only the paths you changed for the task (`git add <paths>`, not `git add -A`). Never commit lockfiles from a parallel agent worktree.
- Ask before adding a dependency, changing the database schema, or deleting files.
- Never invent results: a check passed only if you ran it and saw it pass. Done means the command output or the running app shows the task working, not that nothing errored.
- When you hand work back, say what did not happen: anything not run, not deployed, not applied, not merged.
- Record what you verified in `docs/verification.md` when the change affects a flow a person relies on.

## Verification loops

Run the smallest loop that covers the change, and finish with `mise run verify` before handing work back:

| Loop     | Command                                                  | Covers                                                                                                                                                                     |
| -------- | -------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Inner    | `mise run test`, `mise run check`                        | Unit and config tests (including the wrangler binding guard), types (svelte-check, tsc, astro)                                                                             |
| Pre-push | `mise run verify`                                        | Workflow lint, fmt check, types, lint, tests, build (including `wrangler deploy --dry-run`)                                                                                |
| Database | `mise run test:integration`                              | Integration tests against a disposable Postgres (`mise run infra:up` first)                                                                                                |
| Browser  | `mise run test:e2e`                                      | Playwright at desktop and phone sizes: page errors, console errors, failed requests, sideways scroll                                                                       |
| Infra    | `mise run infra:check`                                   | `tofu fmt`, `validate` and mocked `tofu test`, offline                                                                                                                     |
| CI       | `checks.yml`, `infra.yml` (Blacksmith or GitHub runners) | All of the above, with a Postgres service container                                                                                                                        |
| Release  | `deploy.yml` → `scripts/release.sh`                      | Staging on merge to `main`, production on a `v*` tag; fails on leftover `REPLACE_WITH_` values, a missing migration URL, a failing `/healthz`, or a host not behind Access |
| Runtime  | cron in `apps/worker`                                    | Better Stack heartbeat per schedule once monitoring is on; a missed ping opens an incident                                                                                 |

When CI fails, reproduce it locally with the same `mise run` task before changing code. Do not skip, disable or loosen a check to get green.

## Extension pattern

For each feature, add a browser-safe model/component under `apps/web/src/lib/features/<feature>`, server operations under `apps/web/src/lib/server/<feature>`, thin routes under `apps/web/src/routes`, schema changes in `packages/db`, and colocated tests. Add a worker contract and processor only when the feature needs background work, and a scheduled task by naming it in `SCHEDULES`. A new Cloudflare binding goes in the top level and in both `env` blocks of `wrangler.jsonc` (Wrangler does not inherit them; `tests/config/wrangler.test.ts` fails otherwise), and its resource goes in `infra/cloud/modules/workspace`.
