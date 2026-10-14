import { expect, test } from "@playwright/test";

test("starter home loads", async ({ page }) => {
  await page.goto("/");
  await expect(page.getByRole("heading", { name: "Build your next project here." })).toBeVisible();
  await expect(page.getByRole("link", { name: "Open the example feature" })).toHaveAttribute("href", "/app/items");
});
