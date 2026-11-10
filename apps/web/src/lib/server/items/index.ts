import { items } from "@starter/db/schema";
import { desc } from "drizzle-orm";
import { getDb } from "../db";

export async function listItems() {
  return getDb().select().from(items).orderBy(desc(items.createdAt));
}

export async function createItem(title: string) {
  const [item] = await getDb().insert(items).values({ title }).returning();
  return item;
}
