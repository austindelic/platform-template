import { expect, test } from "vitest";
import { PUBLIC_PATHS, secureHeaders } from "./security";

test("responses are not stored by default and get hardening headers", () => {
  const response = secureHeaders(new Response("x"));
  expect(response.headers.get("cache-control")).toBe("private, no-store");
  expect(response.headers.get("referrer-policy")).toBe("same-origin");
  expect(response.headers.get("x-content-type-options")).toBe("nosniff");
});

test("private immutable responses keep their cache header", () => {
  const response = secureHeaders(
    new Response("x", { headers: { "cache-control": "private, max-age=31536000, immutable" } }),
  );
  expect(response.headers.get("cache-control")).toBe("private, max-age=31536000, immutable");
});

test("only /healthz skips Access", () => {
  expect([...PUBLIC_PATHS]).toEqual(["/healthz"]);
});
