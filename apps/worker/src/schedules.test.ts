import { describe, expect, test, vi } from "vitest";
import { HEARTBEAT_SECRETS, heartbeatUrl, runSchedule } from "./schedules";

const cron = "*/15 * * * *";

describe("heartbeatUrl", () => {
  test("is null without the secret", () => {
    expect(heartbeatUrl(cron, {}, true)).toBeNull();
  });
  test("pings the URL on success and /fail on failure", () => {
    const env = { [HEARTBEAT_SECRETS[cron]]: "https://beat.example/abc/" };
    expect(heartbeatUrl(cron, env, true)).toBe("https://beat.example/abc/");
    expect(heartbeatUrl(cron, env, false)).toBe("https://beat.example/abc/fail");
  });
});

describe("runSchedule", () => {
  const env = { [HEARTBEAT_SECRETS[cron]]: "https://beat.example/abc" };

  test("a failing task does not stop the others, pings /fail and rethrows", async () => {
    const fetcher = vi.fn(async () => new Response("ok"));
    const ran: string[] = [];
    vi.spyOn(console, "error").mockImplementation(() => {});
    await expect(
      runSchedule(
        cron,
        env,
        async (task) => {
          ran.push(task);
          throw new Error("boom");
        },
        fetcher,
      ),
    ).rejects.toBeInstanceOf(AggregateError);
    expect(ran).toEqual(["sweep_stale_jobs"]);
    expect(fetcher).toHaveBeenCalledWith("https://beat.example/abc/fail", expect.anything());
  });

  test("a heartbeat that cannot be sent never fails the run", async () => {
    vi.spyOn(console, "error").mockImplementation(() => {});
    const fetcher = vi.fn(async () => {
      throw new Error("offline");
    });
    await expect(runSchedule(cron, env, async () => {}, fetcher)).resolves.toBeUndefined();
  });
});
