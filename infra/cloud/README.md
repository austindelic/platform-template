# Cloud: Cloudflare, OpenTofu and Infisical

Two OpenTofu roots, `environments/staging` and `environments/production`, share two modules:

- `modules/workspace`: the private R2 bucket, the Hyperdrive config (once a database exists) and the Workers' custom domains.
- `modules/access`: Cloudflare Access in front of a hostname. Staff sign in through a Google identity provider. Machine paths are either app-authenticated (`bypass`) or limited to this app's own service tokens (`service_token`), with optional Managed OAuth for MCP clients.

The Worker scripts, their bindings and their secrets belong to Wrangler (`apps/*/wrangler.jsonc`, `scripts/release.sh`). OpenTofu creates only the resources the Workers point at. CI never runs `plan` or `apply`: it runs only the offline `check.sh` (fmt, validate, and mocked `tofu test`), and every apply is a reviewed run by hand.

## Secrets model

Infisical is the single secret store. Projects are split by **who reads them**, each with one environment, slug `main`:

| Project                           | Holds                                                                                                     | Read by                                                                      |
| --------------------------------- | --------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------- |
| `<app>-dev`                       | Local development values                                                                                  | Humans (`infisical init` → `.infisical.json`, ignored)                       |
| `<app>-deploy-staging` / `-prod`  | `CLOUDFLARE_API_TOKEN` (deploy, one per env), `CLOUDFLARE_ACCOUNT_ID`, `DATABASE_URL_DIRECT` (migrations) | CI only, over GitHub OIDC                                                    |
| `<app>-runtime-staging` / `-prod` | Worker secrets: app keys, third-party API keys, Sentry DSN, heartbeat URLs                                | Nobody in CI. Infisical's Cloudflare Workers sync pushes them to the Workers |
| shared humans-only infra project  | Cloudflare minter token, R2 state-bucket key, vendor root tokens                                          | Humans running `tofu`                                                        |

These values never go in Infisical: the OpenTofu state passphrase (`TF_VAR_state_passphrase`) and recovery codes. They live in the password manager.

CI signs in with `Infisical/secrets-action` (`method: oidc`, audience `https://app.infisical.com`). The GitHub environments `staging` and `production` each hold two variables, `INFISICAL_IDENTITY_ID` and `INFISICAL_PROJECT_ID`. No secret of any kind is stored in GitHub. Pin each identity's OIDC subject to this repo and environment. Orgs that use GitHub's immutable subjects need the form `repo:<owner>@<owner_id>/<repo>@<repo_id>:environment:<env>`.

## First provisioning, in order

1. **State bucket.** Use a private R2 bucket shared across projects (create it once by hand). Copy `backend.hcl.example` to `backend.hcl` in each environment and set the bucket, the key (`<project>/<env>.tfstate`) and the account endpoint.
2. **Inputs.** Copy `terraform.tfvars.example` to `terraform.tfvars` (identifiers only). Export `TF_VAR_state_passphrase` from the password manager.
3. **Plan and apply** with the infra project's credentials (`CLOUDFLARE_API_TOKEN`, plus `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` for the state bucket):

   ```sh
   cd infra/cloud/environments/staging
   infisical run --projectId=<infra project> --env=main -- tofu init -backend-config=backend.hcl
   infisical run --projectId=<infra project> --env=main -- tofu plan -out=tfplan
   infisical run --projectId=<infra project> --env=main -- tofu apply tfplan
   ```

4. **Deploy credentials, minted.** Set `manage_credentials = true` (plus `app_secrets` and, for PlanetScale, `planetscale`) and apply again, with a **minter** Cloudflare token: account-owned, with an expiry, Account API Tokens Write plus every permission it hands on. `modules/credentials` mints the deploy token and the bucket-scoped R2 key with `expires_on` and a 90-day `time_rotating` schedule, plus generated app secrets and dated database roles. Then apply `infra/secrets` ([its README](../secrets/README.md)), which writes them to `<app>-deploy-<env>` and the Worker folders of `<app>-runtime-<env>`. Without a minted migration role, add `DATABASE_URL_DIRECT` to the deploy project by hand.
5. **Wrangler environments.** Copy `tofu output wrangler` into `env.staging` / `env.production` of `apps/web/wrangler.jsonc` and `apps/worker/wrangler.jsonc`, replacing every `REPLACE_WITH_` value. `scripts/release.sh` refuses to deploy while any remain.
6. **Runtime secrets.** Add the Worker secrets to `<app>-runtime-<env>`, then connect the Infisical Cloudflare Workers sync for each Worker.
7. **First deploy.** Run `mise run release staging` by hand, or set the repository variable `DEPLOY_ENABLED=true` and merge to `main`. Then set `attach_worker_domains = true` and apply again so the custom domain points at the Worker.
8. **Check it.** `curl -fsS https://<host>/healthz` must answer `ok`, not an Access login page.

Production repeats steps 1 to 8 with its own state key, Infisical projects and identity. Staging and production never share a project, token or identity.

## Changing infrastructure

Every plan and apply of an environment root replaces whatever tokens are due; follow it with `infra/secrets`. `tofu output credentials_expire` says when each expires.

Edit the module or root, then run `mise run infra:check`. Add a `tests/*.tftest.hcl` run for new behaviour (mock the provider). After changing a provider pin, run `tofu providers lock -platform=linux_amd64 -platform=linux_arm64 -platform=darwin_arm64` in each root and commit the lock files. A first lock attempt can time out on the registry; run it again.
