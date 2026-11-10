import { drizzle } from "drizzle-orm/node-postgres";
import { Pool } from "pg";
import * as schema from "./schema";

/**
 * Create once per request (apps/web/src/lib/server/db.ts) or per operation, and close with
 * db.$client.end(). Accepts a connection string or a Hyperdrive binding.
 */
export function createDb(binding: string | { connectionString: string }) {
  const connectionString = typeof binding === "string" ? binding : binding.connectionString;
  if (!connectionString?.trim()) throw new Error("A PostgreSQL connection string is required.");
  const pool = new Pool({ connectionString });
  return drizzle(pool, { schema });
}

export type Db = ReturnType<typeof createDb>;
