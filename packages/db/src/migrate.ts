import { migrate } from "drizzle-orm/node-postgres/migrator";
import { createDb } from "./index";

const connectionString = process.env.DATABASE_URL;
if (!connectionString) throw new Error("DATABASE_URL is required");
const db = createDb(connectionString);
try {
  await migrate(db, { migrationsFolder: new URL("../migrations-postgres", import.meta.url).pathname });
} finally {
  await db.$client.end();
}
