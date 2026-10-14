import type { ExampleJob } from "../contracts";

/** Replace with bounded, retryable domain processing. */
export async function processJob(job: ExampleJob): Promise<string> {
  return job.text.toUpperCase();
}
