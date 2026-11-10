import { test as base, expect, type Page } from "@playwright/test";
export { expect };

export const WEB_PORT = "5177";

/**
 * Keeps tests from acting before SvelteKit has hydrated the page (the root layout marks
 * `<html data-hydrated>`). On a cold dev server on a small CI runner a click can otherwise land
 * before Svelte attaches its handlers and silently do nothing. `goto` and `reload` wait for the
 * marker; until it is set the page ignores pointer events, so Playwright retries clicks.
 */
async function waitForHydration(page: Page) {
  await page.addInitScript((port) => {
    if (location.port !== port) return;
    const sheet = new CSSStyleSheet();
    sheet.replaceSync("html:not([data-hydrated]) body { pointer-events: none; }");
    document.adoptedStyleSheets = [...document.adoptedStyleSheets, sheet];
  }, WEB_PORT);
  for (const name of ["goto", "reload"] as const) {
    const original = page[name].bind(page) as (...args: unknown[]) => ReturnType<Page["goto"]>;
    page[name] = (async (...args: unknown[]) => {
      const response = await original(...args);
      const url = new URL(page.url());
      if (url.port === WEB_PORT && response?.headers()["content-type"]?.includes("text/html"))
        await page.locator("html[data-hydrated]").waitFor({ state: "attached" });
      return response;
    }) as never;
  }
  return page;
}

/**
 * `problems` collects page errors, console errors and same-origin 4xx/5xx responses; a test
 * ends by expecting it to be empty.
 */
export const test = base.extend<{ problems: string[] }>({
  problems: async ({ page, baseURL }, use) => {
    const problems: string[] = [];
    page.on("pageerror", (error) => problems.push(`page error: ${error.message}`));
    page.on("console", (message) => {
      if (message.type() === "error") problems.push(`console: ${message.text()}`);
    });
    page.on("response", (response) => {
      if (response.status() >= 400 && baseURL && response.url().startsWith(baseURL))
        problems.push(`${response.status()} ${response.url()}`);
    });
    await use(problems);
  },
  page: async ({ page }, use) => {
    await use(await waitForHydration(page));
  },
});

/** Fails when the page scrolls sideways at the current viewport. */
export async function expectNoHorizontalOverflow(page: Page) {
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - innerWidth);
  expect(overflow, "horizontal overflow in px").toBeLessThanOrEqual(0);
}
