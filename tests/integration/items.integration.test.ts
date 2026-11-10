import { items } from "@starter/db/schema";
import { desc } from "drizzle-orm";
import { expect, test } from "vitest";
import { postgresTestDatabase } from "./helpers/postgres";

const database = postgresTestDatabase();

test("items round-trip through the migrated schema", async () => {
  const [created] = await database.db.insert(items).values({ title: "First item" }).returning();
  expect(created.title).toBe("First item");
  const rows = await database.db.select().from(items).orderBy(desc(items.createdAt));
  expect(rows.map((row) => row.title)).toEqual(["First item"]);
});
