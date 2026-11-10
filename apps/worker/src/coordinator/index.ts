import { instrumentDurableObjectWithSentry, withSentry } from "@sentry/cloudflare";
import { decodeJob } from "../contracts";
import { consumeBatch, decodeQueueMessage, sendToQueue } from "../queues";
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
    // Queues do not connect between `vite dev` and `wrangler dev`, so locally the web app (or a
    // person) enqueues through this Worker. Never in a hosted environment.
    if (
      url.pathname === "/__dev/enqueue" &&
      request.method === "POST" &&
      env.ENVIRONMENT === "local"
    ) {
      const message = decodeQueueMessage(await request.json().catch(() => null));
      if (!message) return Response.json({ error: "Invalid queue message" }, { status: 400 });
      await sendToQueue(env, message);
      return Response.json({ queued: message.kind }, { status: 202 });
    }
    const match = /^\/jobs\/([0-9a-f-]{36})$/.exec(url.pathname);
    if (match && request.method === "GET") {
      return env.JOB_RUNNER.get(env.JOB_RUNNER.idFromName(match[1])).fetch("https://job.internal/");
    }
    return new Response("Not found", { status: 404 });
  },
  /** Consumer for every bound queue (none until one is added; infra/cloud/README.md, Queues). */
  async queue(batch: MessageBatch<unknown>, _env: Env): Promise<void> {
    await consumeBatch(batch, async (message) => {
      console.log(JSON.stringify({ event: "queue.example", id: message.id }));
    });
  },
  async scheduled(controller: ScheduledController, env: Env): Promise<void> {
    await runSchedule(controller.cron, env, (task) => runScheduledTask(task, env));
  },
} satisfies ExportedHandler<Env>);
