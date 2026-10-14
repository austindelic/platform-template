export { JobRunner } from "./job-runner";
import { decodeJob } from "../contracts";

interface Env { JOB_RUNNER: DurableObjectNamespace }

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname === "/health" && request.method === "GET") {
      return Response.json({ status: "ok" });
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
} satisfies ExportedHandler<Env>;
