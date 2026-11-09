/**
 * Creates the local S3-compatible bucket after `docker compose up` (run by `bun run infra:up`).
 * Local only: it refuses any endpoint that is not on 127.0.0.1 or localhost.
 */
import { createStorage } from "@starter/storage";

const endpoint = process.env.STORAGE_ENDPOINT ?? "http://127.0.0.1:59000";
const host = new URL(endpoint).hostname;
if (host !== "127.0.0.1" && host !== "localhost") {
  console.error(`Refusing to create a bucket on ${host}: this script is for local storage only.`);
  process.exit(1);
}

const bucket = process.env.STORAGE_BUCKET ?? "platform-starter";
const storage = createStorage({
  endpoint,
  bucket,
  region: process.env.STORAGE_REGION ?? "us-east-1",
  accessKeyId: process.env.STORAGE_ACCESS_KEY ?? "LOCALSTORAGE",
  secretAccessKey: process.env.STORAGE_SECRET_KEY ?? "local-storage-secret",
});

for (let attempt = 1; ; attempt++) {
  try {
    if (await storage.bucketExists()) {
      console.log(`Local bucket ${bucket} exists.`);
    } else {
      await storage.createBucket();
      console.log(`Created local bucket ${bucket}.`);
    }
    break;
  } catch (error) {
    if (attempt >= 10) throw error;
    await new Promise((resolve) => setTimeout(resolve, 1000));
  }
}
