# Platform starter

A generic starter extracted from the architecture of Next Frame. It keeps the same workspace boundaries without product content, credentials, release identities, or media workflows.

## Start locally

1. Install mise and Docker with Compose v2. Run `mise trust && mise install`.
2. Run `mise exec -- bun install`.
3. Run `mise exec -- infisical login`, then `mise exec -- infisical init` and select **your new Infisical project**. The generated `.infisical.json` is ignored so this template cannot point at the source project's workspace.
4. Add the keys shown in `.env.example` to that project's `dev` environment. These are disposable local defaults; set `DATABASE_URL` to the local PostgreSQL port shown there.
5. Run `mise run infra:up`, `mise run db:migrate`, then `mise run dev`. Open the web app at `http://127.0.0.1:5177` and handbook at `http://127.0.0.1:4323`.

`mise run dev` and `mise run db:migrate` fetch the `dev` environment through the pinned Infisical CLI. Direct `bun run` commands are for checks or for deliberately supplied process environments. Keep local credentials in Infisical; `.env.example` is a key inventory, not a required local file.

The example Items page exercises SvelteKit route → server operation → shared Drizzle schema. The Jobs Worker illustrates the private service-binding and processor boundary. The storage adapter is ready for a feature that needs object storage.

## Before a real launch

Rename package/Worker identifiers and local ports, add your authentication and access policy, define your domain schema, configure cloud resources and separate staging/production Infisical identities, review the deployment boundary in `infra/cloud`, and replace the example feature. The cloud files are deliberately provisioning templates; they do not deploy without project-specific settings.

Run `mise exec -- bun run check`, `mise exec -- bun run test`, and `mise exec -- bun run build` before using the starter. See [AGENTS.md](AGENTS.md) for code ownership.
