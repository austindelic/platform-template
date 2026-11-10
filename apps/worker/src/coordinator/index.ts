import { instrumentDurableObjectWithSentry, withSentry } from "@sentry/cloudflare";
import { decodeJob } from "../contracts";
import { runSchedule } from "../schedules";
import { JobRunner as JobRunnerBase } from "./job-runner";
import { runScheduledTask } from "./sweep";

export interface Env {
  JOB_RUNNER: DurableObjectNamespace;
  ENVIRONMENT?: string;
  /** Worker secret. Without it Sentry stays off; personal data is not sent either way. */
  SENTRY_DSN?: string;
  /** Better Stack heartbeat for the sweep schedule (schedules.ts). Unset: no ping. */
  HEARTBEAT_URL_SWEEP?: string;
}

const sentryOptions = (env: Env) => ({ dsn: env.SENTRY_DSN, environment: env.ENVIRONMENT });

export const JobRunner = instrumentDurableObjectWithSentry(sentryOptions, JobRunnerBase);

export default withSentry(sentryOptions, {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if ((url.pathname === "/healthz" || url.pathname === "/health") && request.method === "GET") {
      return new Response("ok", { headers: { "content-type": "text/plain" } });
    }
    if (url.pathname === "/jobs" && request.method === "POST") {
      const job = decodeJob(await request.json().catch(() => null));
      if (!job) return Response.json({ error: "Invalid job" }, { status: 400 });
      return env.JOB_RUNNER.get(env.JOB_RUNNER.idFromName(job.id)).fetch(
        new Request("https://job.internal/", { method: "POST", body: JSON.stringify(job) }),
      );
    }
    const match = /^\/jobs\/([0-9a-f-]{36})$/.exec(url.pathname);
    if (match && request.method === "GET") {
      return env.JOB_RUNNER.get(env.JOB_RUNNER.idFromName(match[1])).fetch("https://job.internal/");
    }
    return new Response("Not found", { status: 404 });
  },
  async scheduled(controller: ScheduledController, env: Env): Promise<void> {
    await runSchedule(controller.cron, env, (task) => runScheduledTask(task, env));
  },
} satisfies ExportedHandler<Env>);
