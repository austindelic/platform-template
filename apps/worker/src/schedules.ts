/**
 * Cron Triggers and the tasks each runs. Keep the keys in step with `triggers.crons` in every
 * block of wrangler.jsonc (schedules.test.ts checks it).
 */
export const SCHEDULES = {
  "*/15 * * * *": ["sweep_stale_jobs"],
} as const satisfies Record<string, readonly string[]>;

export type ScheduledTask = (typeof SCHEDULES)[keyof typeof SCHEDULES][number];

export function tasksForCron(cron: string): readonly ScheduledTask[] {
  return (SCHEDULES as Record<string, readonly ScheduledTask[]>)[cron] ?? [];
}

/**
 * The Worker secret holding each schedule's Better Stack heartbeat URL (HEARTBEAT_URL_<JOB>,
 * created by infra/monitoring when it is switched on). One per schedule, not per task.
 */
export const HEARTBEAT_SECRETS = {
  "*/15 * * * *": "HEARTBEAT_URL_SWEEP",
} as const satisfies Record<keyof typeof SCHEDULES, string>;

/**
 * The URL to request when a run ends: the heartbeat on success, `<heartbeat>/fail` on failure.
 * Null when the schedule has no heartbeat or its secret is not set (local dev, monitoring off).
 */
export function heartbeatUrl(cron: string, env: object, ok: boolean): string | null {
  const secret = (HEARTBEAT_SECRETS as Record<string, string>)[cron];
  const url = secret ? (env as Record<string, unknown>)[secret] : undefined;
  if (typeof url !== "string" || !url) return null;
  return ok ? url : `${url.replace(/\/+$/, "")}/fail`;
}

/**
 * Runs every task of one schedule. Tasks run side by side and one failure never skips another;
 * the heartbeat is pinged at the end (success or /fail), a failed ping never fails the run, and
 * the run then rethrows so Cron Trigger history shows it failed.
 */
export async function runSchedule(
  cron: string,
  env: object,
  run: (task: ScheduledTask) => Promise<void>,
  fetcher: typeof fetch = fetch,
): Promise<void> {
  const tasks = tasksForCron(cron);
  if (tasks.length === 0) console.error(JSON.stringify({ event: "cron.unknown", cron }));
  const results = await Promise.allSettled(tasks.map((task) => run(task)));
  const failed: unknown[] = [];
  results.forEach((result, i) => {
    if (result.status === "fulfilled") return;
    failed.push(result.reason);
    console.error(
      JSON.stringify({ event: "cron.failed", cron, task: tasks[i], error: String(result.reason) }),
    );
  });
  const ping = heartbeatUrl(cron, env, failed.length === 0);
  if (ping && tasks.length) {
    await fetcher(ping, { method: "GET", signal: AbortSignal.timeout(5000) })
      .then((response) => response.body?.cancel())
      .catch((error: unknown) =>
        console.error(
          JSON.stringify({ event: "cron.heartbeat_failed", cron, error: String(error) }),
        ),
      );
  }
  if (failed.length)
    throw new AggregateError(failed, `${failed.length} of ${tasks.length} scheduled tasks failed`);
}
