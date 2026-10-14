import { describe, expect, it } from "vitest";
import { decodeJob } from "./contracts";

describe("decodeJob", () => {
  it("accepts a bounded payload", () => {
    expect(decodeJob({ id: "12345678-1234-1234-1234-123456789abc", text: " hello " })).toEqual({
      id: "12345678-1234-1234-1234-123456789abc", text: "hello",
    });
  });
  it("rejects invalid payloads", () => expect(decodeJob({ id: "x", text: "hello" })).toBeNull());
});
