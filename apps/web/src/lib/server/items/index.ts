import { createDb } from "@starter/db";
import { items } from "@starter/db/schema";
import { desc } from "drizzle-orm";

export async function listItems(connectionString: string) {
  const db = createDb(connectionString);
  try {
    return await db.select().from(items).orderBy(desc(items.createdAt));
  } finally {
    await db.$client.end();
  }
}

export async function createItem(connectionString: string, title: string) {
  const db = createDb(connectionString);
  try {
    const [item] = await db.insert(items).values({ title }).returning();
    return item;
  } finally {
    await db.$client.end();
  }
}
