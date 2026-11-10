import { expect, test } from "./fixtures";

test("starter home links to the example feature", async ({ page, problems }) => {
  await page.goto("/");
  await expect(page.getByRole("heading", { name: "Build your next project here." })).toBeVisible();
  await expect(page.getByRole("link", { name: "Open the example feature" })).toHaveAttribute(
    "href",
    "/app/items",
  );
  expect(problems).toEqual([]);
});
