import { randomUUID } from "node:crypto";
import { fileURLToPath } from "node:url";
import { createDb } from "@starter/db";
import { readMigrationFiles } from "drizzle-orm/migrator";
import { afterAll, beforeAll } from "vitest";

// Explicit opt-in only. Never use the application's DATABASE_URL. Each suite gets its own schema
// with every migration applied, dropped afterwards, so suites can run in parallel.
export const testDatabaseUrl = process.env.TEST_DATABASE_URL;

export function postgresTestDatabase(migrationCount?: number) {
  const schemaName = `web_test_${randomUUID().replaceAll("-", "")}`;
  let admin: ReturnType<typeof createDb> | undefined;
  let db: ReturnType<typeof createDb>;
  let created = false;

  beforeAll(async () => {
    if (!testDatabaseUrl) throw new Error("TEST_DATABASE_URL is required");
    const url = new URL(testDatabaseUrl);
    url.searchParams.set("connection_timeout", "5");
    admin = createDb(url.toString());
    await admin.$client.query(`CREATE SCHEMA "${schemaName}"`);
    created = true;
    url.searchParams.set("options", `-c search_path=${schemaName} -c statement_timeout=10000`);
    url.searchParams.set("application_name", schemaName);
    db = createDb(url.toString());
    const migrations = readMigrationFiles({
      migrationsFolder: fileURLToPath(
        new URL("../../../packages/db/migrations-postgres", import.meta.url),
      ),
    });
    for (const migration of migrations.slice(0, migrationCount)) {
      for (const statement of migration.sql) {
        // Generated foreign keys explicitly reference public; isolate those too.
        await db.$client.query(statement.replaceAll('"public".', `"${schemaName}".`));
      }
    }
  }, 30000);

  afterAll(async () => {
    try {
      await db?.$client.end();
    } finally {
      try {
        if (created) await admin!.$client.query(`DROP SCHEMA "${schemaName}" CASCADE`);
      } finally {
        await admin?.$client.end();
      }
    }
  }, 30000);

  return {
    get db() {
      return db;
    },
    schemaName,
  };
}
