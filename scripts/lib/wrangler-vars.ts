/**
 * Prints `KEY=value` lines for one hosted env's vars from an app's wrangler.jsonc (comments
 * allowed), optionally only keys with a prefix:
 *
 *   bun --no-env-file scripts/lib/wrangler-vars.ts apps/web/wrangler.jsonc staging STORAGE_
 */
import { readFileSync } from "node:fs";
import ts from "typescript";

const [path, environment, prefix = ""] = process.argv.slice(2);
if (!path || !environment) {
  console.error("Usage: wrangler-vars.ts <wrangler.jsonc> <staging|production> [prefix]");
  process.exit(2);
}
const { config, error } = ts.parseConfigFileTextToJson(path, readFileSync(path, "utf8"));
if (error) {
  console.error(`${path} is not valid JSONC.`);
  process.exit(1);
}
const vars: Record<string, string> = config?.env?.[environment]?.vars ?? {};
for (const [key, value] of Object.entries(vars))
  if (key.startsWith(prefix)) console.log(`${key}=${value}`);
