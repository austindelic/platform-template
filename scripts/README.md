# Operator scripts

Use this boundary for repeatable local lifecycle, migration, backup, and cloud release commands. Keep deployment approvals, state locks, and backup/restore checks separate from application routes and background jobs. The starter provides package scripts for local services and migrations; add provider-specific release commands only after the new project has reviewed infrastructure and credentials.

Local dev and migrations run under `infisical run --env=dev` through `mise.toml`. Use new-project Infisical identities for future cloud scripts; do not reuse local login or a production identity in CI.
