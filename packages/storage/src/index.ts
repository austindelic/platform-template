import { S3mini } from "s3mini";

export interface StorageConfig {
  endpoint: string;
  bucket: string;
  region: string;
  accessKeyId: string;
  secretAccessKey: string;
}

export function createStorage(config: StorageConfig): S3mini {
  return new S3mini({
    ...config,
    endpoint: `${config.endpoint.replace(/\/+$/, "")}/${encodeURIComponent(config.bucket)}`,
  });
}
