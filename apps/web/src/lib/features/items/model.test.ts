import { describe, expect, it } from "vitest";
import { parseItemTitle } from "./model";

describe("parseItemTitle", () => {
  it("trims a valid title", () => expect(parseItemTitle("  Example  ")).toBe("Example"));
  it("rejects empty and oversized titles", () => {
    expect(parseItemTitle("   ")).toBeNull();
    expect(parseItemTitle("x".repeat(121))).toBeNull();
  });
});
