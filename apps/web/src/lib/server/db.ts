import { createDb } from "@starter/db";
import { getRequestEvent } from "$app/server";
import { env } from "$env/dynamic/private";
import { AsyncLocalStorage } from "node:async_hooks";

export type Database = Omit<ReturnType<typeof createDb>, "$client">;
const transactions = new AsyncLocalStorage<Database>();

/**
 * One pool per request, created on first use and closed by hooks.server.ts. Hosted Workers use
 * the Hyperdrive binding; local tools without a platform fall back to DATABASE_URL.
 */
export function getDatabaseConnection() {
  const event = getRequestEvent();
  const binding = event.platform?.env.HYPERDRIVE ?? env.DATABASE_URL;
  if (!binding) throw new Error("The database is not configured (HYPERDRIVE or DATABASE_URL).");
  return (event.locals.db ??= createDb(binding));
}

/** The current transaction when inside inDatabaseTransaction, else the request's connection. */
export function getDb(): Database {
  return transactions.getStore() ?? getDatabaseConnection();
}

/** Feature services called inside `work` share the transaction; the request still owns the pool. */
export function inDatabaseTransaction<T>(work: () => Promise<T>) {
  return getDb().transaction((tx) => transactions.run(tx, work));
}
