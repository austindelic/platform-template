import { expect, expectNoHorizontalOverflow, test } from "./fixtures";

// Every page renders at desktop and phone sizes with no errors, failed requests or sideways
// scrolling. Pages that need the database run only when E2E_WITH_DATABASE=1 (CI, or locally after
// `mise run infra:up && mise run db:migrate`).
const routes = ["/", ...(process.env.E2E_WITH_DATABASE === "1" ? ["/app/items"] : [])];

for (const route of routes) {
  test(`renders ${route}`, async ({ page, problems }) => {
    const response = await page.goto(route);
    expect(response?.status()).toBe(200);
    await expect(page.locator("h1").first()).toBeVisible();
    await expectNoHorizontalOverflow(page);
    expect(problems).toEqual([]);
  });
}

test("/healthz answers ok without a page", async ({ request }) => {
  const response = await request.get("/healthz");
  expect(response.status()).toBe(200);
  expect(await response.text()).toBe("ok");
});

test("unknown routes return 404", async ({ page }) => {
  const response = await page.goto("/no-such-page");
  expect(response?.status()).toBe(404);
});
