# Platform starter

## Architecture

- `apps/web` owns HTTP routes and presentation. Keep route files thin; put browser-safe models/components in `src/lib/features` and database workflows in `src/lib/server`.
- `apps/worker` owns private asynchronous work. Keep payload contracts in `src/contracts.ts`, coordination in `src/coordinator`, and bounded processing in `src/processor`.
- `apps/docs` is the staff-facing Astro handbook. Keep its user instructions aligned with the app.
- `packages/db` owns the PostgreSQL schema, migrations, and adapter. `packages/storage` owns the S3-compatible adapter. Apps import packages, never each other's source.
- `infra/local` owns disposable local services. `infra/cloud` separates staging and production provisioning plans. `scripts` holds operator tasks. `tests` holds cross-package integration and browser tests.

## Development

Use pinned tools from `mise.toml`. Start local services, apply migrations, then run the apps. Load local secrets through the pinned Infisical CLI and project-local `.infisical.json`. Never copy a source workspace ID, commit credentials, or reuse cloud identities between environments. Add authentication and authorization before exposing application data. Test the affected layer and browser flow after changes.

## Extension pattern

For each feature, add a browser-safe model/component under `apps/web/src/lib/features/<feature>`, server operations under `apps/web/src/lib/server/<feature>`, thin routes under `apps/web/src/routes`, schema changes in `packages/db`, and colocated tests. Add a worker contract and processor only when the feature needs background work.
