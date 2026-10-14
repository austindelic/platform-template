import { fail } from "@sveltejs/kit";
import { parseItemTitle } from "$lib/features/items/model";
import { createItem, listItems } from "$lib/server/items";
import type { Actions, PageServerLoad } from "./$types";

function databaseUrl(platform: App.Platform | undefined): string {
  const value = process.env.DATABASE_URL ?? platform?.env.HYPERDRIVE?.connectionString;
  if (!value) throw new Error("Database connection is not configured");
  return value;
}

export const load: PageServerLoad = async ({ platform }) => ({
  items: await listItems(databaseUrl(platform)),
});

export const actions: Actions = {
  default: async ({ request, platform }) => {
    const title = parseItemTitle((await request.formData()).get("title"));
    if (!title) return fail(400, { message: "Enter a title of 1–120 characters." });
    await createItem(databaseUrl(platform), title);
    return { message: "Item added." };
  },
};
