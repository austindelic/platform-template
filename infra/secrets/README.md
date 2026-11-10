# secrets

Writes the credentials the other OpenTofu roots mint into Infisical. It uses the same encrypted R2 state as the other roots (key `platform-starter/secrets.tfstate`), reads them through `terraform_remote_state`, and writes with `infisical_secret` `value_wo`, so no second copy of a value sits in this root's state.

**Run only by a person, from a laptop. Never in CI.** It does nothing until the source roots have been applied with `manage_credentials = true` and the project IDs are set.

## What it reads and writes

Nothing is minted here. Each source root exposes a sensitive `secrets` output and a printable `secret_names` output, keyed by destination:

| Source root (state key)                                                       | Mints                                                                                                                      |
| ----------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| `infra/cloud/environments/staging` (`platform-starter/staging.tfstate`)       | Deploy token, R2 storage key, generated app secrets; database roles with a dedicated PlanetScale branch                    |
| `infra/cloud/environments/production` (`platform-starter/production.tfstate`) | The same, plus backup keys and a 7-day migration role (`deploy` `DATABASE_URL_DIRECT`) when backups and PlanetScale are on |
| `infra/monitoring` (`platform-starter/monitoring.tfstate`), if present        | Sentry DSN and Better Stack heartbeat URLs                                                                                 |

| Destination        | Infisical project (env `main`) and folder                                      |
| ------------------ | ------------------------------------------------------------------------------ |
| `runtime/<folder>` | `<app>-runtime-<env>`, one folder per Worker (`runtime_folders`, created here) |
| `deploy`           | `<app>-deploy-<env>` `/`, read by CI                                           |
| `backups`          | `<app>-backups-prod` `/`, only when `backups_prod` is set                      |

`tofu output secret_names` lists what this root writes; no output ever holds a value. Before writing anything, the plan refuses any of these:

- a destination with no project
- a runtime folder not in `runtime_folders`
- two roots writing the same name to one place
- staging and production database roles on one PlanetScale branch
- a deploy `DATABASE_URL_DIRECT` from a root that does not name its branch

Each `value_wo_version` comes from the value's hash, so a rotation upstream, or a deliberate `-replace` there, is rewritten on the next apply here. Third-party keys pasted by hand into the same projects are never touched.

## Running

The Infisical provider signs in only as a machine identity. On a plan with few identities, create a temporary universal-auth identity before each run, make it Admin on this app's projects only, and delete it afterwards. Credentials go into the shell for the one command, never into files:

```sh
export TF_VAR_state_passphrase=...            # password manager; also opens the source states
export INFISICAL_UNIVERSAL_AUTH_CLIENT_ID=... # temporary identity: create before, delete after
export INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET=...
export AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=...   # R2 state key (reads the source states too)
tofu init -backend-config=backend.hcl
tofu plan -out=tfplan   # read it, then:
tofu apply tfplan
```

Use one state passphrase for every root in a repo. A source written with a different passphrase can't be read from R2. Read its outputs with `./source-outputs.sh <source>` (with `PASSPHRASE_<SOURCE>` set) into `TF_VAR_given_outputs`, list it in `TF_VAR_given_output_sources`, and keep the value in the shell only.

Run this root after every apply of a source root. Put a reminder in the calendar for the rotation: plan and apply the environment roots, then this root, about every 60 days. Check `tofu output credentials_expire` for the dates. A minted migration role lapses `migration_role_ttl_days` after each apply. Before a release after that date, apply production and then this root, or the release stops at its migrations step.
