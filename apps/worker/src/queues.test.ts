import { describe, expect, test, vi } from "vitest";
import { consumeBatch, decodeQueueMessage, retryDelaySeconds, sendToQueue } from "./queues";

function message(body: unknown, attempts = 1) {
  return { id: "m1", body, attempts, ack: vi.fn(), retry: vi.fn() };
}

describe("consumeBatch", () => {
  test("acks a handled message", async () => {
    const m = message({ kind: "example", id: "a" });
    await consumeBatch({ queue: "q", messages: [m] }, async () => {});
    expect(m.ack).toHaveBeenCalled();
    expect(m.retry).not.toHaveBeenCalled();
  });

  test("acks an invalid message instead of retrying it forever", async () => {
    vi.spyOn(console, "error").mockImplementation(() => {});
    const m = message({ kind: "unknown" });
    const handle = vi.fn();
    await consumeBatch({ queue: "q", messages: [m] }, handle);
    expect(m.ack).toHaveBeenCalled();
    expect(handle).not.toHaveBeenCalled();
  });

  test("retries a failure with backoff and keeps going", async () => {
    vi.spyOn(console, "error").mockImplementation(() => {});
    const failing = message({ kind: "example", id: "a" }, 3);
    const next = message({ kind: "example", id: "b" });
    await consumeBatch({ queue: "q", messages: [failing, next] }, async (msg) => {
      if (msg.id === "a") throw new Error("boom");
    });
    expect(failing.retry).toHaveBeenCalledWith({ delaySeconds: 120 });
    expect(next.ack).toHaveBeenCalled();
  });
});

test("retry delay doubles and caps at 15 minutes", () => {
  const msg = { kind: "example", id: "a" } as const;
  expect([1, 2, 3, 10].map((n) => retryDelaySeconds(msg, n))).toEqual([30, 60, 120, 900]);
});

test("sendToQueue throws without a binding instead of dropping the message", async () => {
  await expect(sendToQueue({}, { kind: "example", id: "a" })).rejects.toThrow("JOBS_QUEUE");
  const send = vi.fn(async () => {});
  await sendToQueue({ JOBS_QUEUE: { send } }, { kind: "example", id: "a" }, 5);
  expect(send).toHaveBeenCalledWith({ kind: "example", id: "a" }, { delaySeconds: 5 });
});

test("decodeQueueMessage rejects malformed bodies", () => {
  expect(decodeQueueMessage(null)).toBeNull();
  expect(decodeQueueMessage({ kind: "example", id: "" })).toBeNull();
});
