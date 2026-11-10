import { DurableObject } from "cloudflare:workers";
import { decodeJob, type ExampleJob, type ExampleJobState } from "../contracts";
import { processJob } from "../processor";
import type { Env } from "./index";

export class JobRunner extends DurableObject<Env> {
  async fetch(request: Request): Promise<Response> {
    if (request.method === "POST") {
      const job = decodeJob(await request.json().catch(() => null));
      if (!job) return Response.json({ error: "Invalid job" }, { status: 400 });
      const existing = await this.ctx.storage.get<ExampleJobState>("status");
      if (existing) return Response.json({ error: "Job already exists" }, { status: 409 });
      await this.ctx.storage.put("job", job);
      await this.ctx.storage.put("status", { status: "queued" } satisfies ExampleJobState);
      await this.ctx.storage.setAlarm(Date.now());
      return Response.json({ id: job.id, status: "queued" }, { status: 202 });
    }
    if (request.method === "GET") {
      const status = await this.ctx.storage.get<ExampleJobState>("status");
      return status
        ? Response.json(status)
        : Response.json({ error: "Not found" }, { status: 404 });
    }
    return new Response(null, { status: 405 });
  }

  async alarm(): Promise<void> {
    const job = await this.ctx.storage.get<ExampleJob>("job");
    if (!job) return;
    await this.ctx.storage.put("status", { status: "running" } satisfies ExampleJobState);
    try {
      const result = await processJob(job);
      await this.ctx.storage.put("status", {
        status: "complete",
        result,
      } satisfies ExampleJobState);
    } catch {
      await this.ctx.storage.put("status", {
        status: "failed",
        error: "Processing failed",
      } satisfies ExampleJobState);
    } finally {
      await this.ctx.storage.delete("job");
    }
  }
}
