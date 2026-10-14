import type { DurableObjectState } from "@cloudflare/workers-types";
import { decodeJob, type ExampleJob, type ExampleJobState } from "../contracts";
import { processJob } from "../processor";

export class JobRunner {
  constructor(private readonly state: DurableObjectState) {}

  async fetch(request: Request): Promise<Response> {
    if (request.method === "POST") {
      const job = decodeJob(await request.json().catch(() => null));
      if (!job) return Response.json({ error: "Invalid job" }, { status: 400 });
      const existing = await this.state.storage.get<ExampleJobState>("status");
      if (existing) return Response.json({ error: "Job already exists" }, { status: 409 });
      await this.state.storage.put("job", job);
      await this.state.storage.put("status", { status: "queued" } satisfies ExampleJobState);
      await this.state.storage.setAlarm(Date.now());
      return Response.json({ id: job.id, status: "queued" }, { status: 202 });
    }
    if (request.method === "GET") {
      const status = await this.state.storage.get<ExampleJobState>("status");
      return status ? Response.json(status) : Response.json({ error: "Not found" }, { status: 404 });
    }
    return new Response(null, { status: 405 });
  }

  async alarm(): Promise<void> {
    const job = await this.state.storage.get<ExampleJob>("job");
    if (!job) return;
    await this.state.storage.put("status", { status: "running" } satisfies ExampleJobState);
    try {
      const result = await processJob(job);
      await this.state.storage.put("status", { status: "complete", result } satisfies ExampleJobState);
    } catch {
      await this.state.storage.put("status", { status: "failed", error: "Processing failed" } satisfies ExampleJobState);
    } finally {
      await this.state.storage.delete("job");
    }
  }
}
