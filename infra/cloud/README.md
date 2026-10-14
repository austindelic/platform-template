# Cloud provisioning boundary

The source project separates staging and production stacks under `environments/`, with reusable `modules/workspace` and `modules/access`. This starter preserves that layout but intentionally creates no cloud resources until a new project chooses its provider account, domains, buckets, database, Access policy, secret store, backup policy, and release approvals. Copying those IDs or policies from the source would be unsafe.

Fill each environment independently, pin provider versions, and add `tofu fmt`, `init -backend=false`, and `validate` to CI before the first provisioning review. Build and verify the protected handbook before publishing web links to it. Keep deployment, promotion, backup, and recovery as reviewed workflows rather than implicit side effects of local development.

## Secrets and identity

Create separate `staging` and `prod` environments in the new project's Infisical workspace. Cloud CI should use environment-scoped machine identities or OIDC with repository, branch, workflow, and environment claims pinned before adding deployment jobs. Load secrets only inside the approved job, mask them in logs, and keep them out of generated Worker configuration and artifacts. No source workspace ID, identity ID, or deployment token is included here.
