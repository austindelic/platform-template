# Integration tests

`mise run test:integration` runs `*.integration.test.ts` against `TEST_DATABASE_URL`, a disposable Postgres (the local one from `mise run infra:up`, or CI's service container). `helpers/postgres.ts` gives each suite its own schema with every migration applied and drops it afterwards. The config refuses to start without `TEST_DATABASE_URL`, and nothing here reads the application's `DATABASE_URL`.
