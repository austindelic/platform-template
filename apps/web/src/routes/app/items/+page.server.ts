import { fail } from "@sveltejs/kit";
import { parseItemTitle } from "$lib/features/items/model";
import { createItem, listItems } from "$lib/server/items";
import type { Actions, PageServerLoad } from "./$types";

export const load: PageServerLoad = async () => ({ items: await listItems() });

export const actions: Actions = {
  default: async ({ request }) => {
    const title = parseItemTitle((await request.formData()).get("title"));
    if (!title) return fail(400, { message: "Enter a title of 1–120 characters." });
    await createItem(title);
    return { message: "Item added." };
  },
};
