import { drizzle } from "drizzle-orm/node-postgres";
import { Pool } from "pg";
import * as schema from "./schema";

/** Create for one operation and close with db.$client.end(). */
export function createDb(connectionString: string) {
  if (!connectionString.trim()) throw new Error("DATABASE_URL is required");
  const pool = new Pool({ connectionString });
  return drizzle(pool, { schema });
}
