# Operator scripts

Repeatable local lifecycle and cloud release commands. Keep deployment approvals, state locks and backup checks here, separate from application routes and background jobs.

- `release.sh staging|production`: migrations over the direct connection, then the jobs Worker, then the web Worker, with an optional `/healthz` check. Run by `.github/workflows/deploy.yml`, or by hand with `mise run release staging`. Secrets come from the `<app>-deploy-<env>` Infisical project (`infra/cloud/README.md`).
- `local-storage.ts`: creates the local bucket after `docker compose up`. Runs from `bun run infra:up`, and refuses non-local endpoints.
- `cloud-session-setup.sh`: the SessionStart hook for Claude Code cloud sessions. It installs the pinned tools and never fails the session.

Never reuse a local Infisical login or a production identity in CI. CI signs in over GitHub OIDC with environment-scoped identities.
