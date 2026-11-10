import type { ScheduledTask } from "../schedules";
import type { Env } from "./index";

/**
 * The example scheduled task. Replace with real recovery work (requeue stuck jobs, purge expired
 * rows); add a task by naming it in SCHEDULES and handling it here.
 */
export async function runScheduledTask(task: ScheduledTask, env: Env): Promise<void> {
  switch (task) {
    case "sweep_stale_jobs":
      console.log(JSON.stringify({ event: "cron.sweep", environment: env.ENVIRONMENT }));
      return;
  }
}
