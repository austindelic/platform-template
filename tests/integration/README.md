# Integration tests

Use a disposable `TEST_DATABASE_URL` and isolated schema for database integration tests. Do not point tests at an application database. The example unit tests in each package run without external services.
