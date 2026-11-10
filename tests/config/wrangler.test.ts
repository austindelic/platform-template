import { readFileSync, readdirSync, existsSync } from "node:fs";
import ts from "typescript";
import { describe, expect, test } from "vitest";
import { SCHEDULES } from "../../apps/worker/src/schedules";

/**
 * Wrangler does not inherit bindings into env blocks: each one must be repeated. A binding that is
 * declared for local dev but missing from env.staging or env.production deploys fine and then
 * fails, or is silently skipped, at runtime (a source repo shipped 1 of 5 queue producers that
 * way). This checks every app's wrangler.jsonc: each env lists every binding name the top level
 * declares, and the jobs Worker's crons match SCHEDULES.
 */
type Block = Record<string, unknown> & { env?: Record<string, Block> };

const root = new URL("../../apps/", import.meta.url);
const configs = readdirSync(root)
  .map((app) => ({ app, path: new URL(`${app}/wrangler.jsonc`, root) }))
  .filter(({ path }) => existsSync(path))
  .map(({ app, path }) => ({
    app,
    config: ts.parseConfigFileTextToJson(path.pathname, readFileSync(path, "utf8")).config as Block,
  }));

/** Binding names by kind, e.g. "queues.producers:JOBS_QUEUE". */
function bindings(block: Block): string[] {
  const names: string[] = [];
  const list = (kind: string, items: unknown, key = "binding") => {
    for (const item of (items as Record<string, string>[] | undefined) ?? [])
      names.push(`${kind}:${item[key] ?? item.name ?? item.queue}`);
  };
  list("hyperdrive", block.hyperdrive);
  list("services", block.services);
  list("r2_buckets", block.r2_buckets);
  list("kv_namespaces", block.kv_namespaces);
  list("d1_databases", block.d1_databases);
  list("send_email", block.send_email, "name");
  list("durable_objects", (block.durable_objects as { bindings?: unknown })?.bindings, "name");
  const queues = block.queues as { producers?: unknown; consumers?: unknown } | undefined;
  list("queues.producers", queues?.producers);
  list("queues.consumers", queues?.consumers, "queue");
  for (const name of Object.keys((block.vars as object) ?? {})) names.push(`vars:${name}`);
  return names.sort();
}

describe.each(configs)("$app/wrangler.jsonc", ({ config }) => {
  const envs = Object.entries(config.env ?? {});

  test("has staging and production environments", () => {
    expect(Object.keys(config.env ?? {}).sort()).toEqual(["production", "staging"]);
  });

  test.each(envs)("env.%s repeats every top-level binding", (_name, block) => {
    // An env may add hosted-only bindings or vars; it must not drop one the top level declares.
    // Queue consumers are compared by count, since their queue names differ per env.
    const strip = (names: string[]) => names.filter((n) => !n.startsWith("queues.consumers:"));
    const missing = strip(bindings(config)).filter((n) => !strip(bindings(block)).includes(n));
    expect(missing).toEqual([]);
    const consumers = (b: Block) =>
      ((b.queues as { consumers?: unknown[] } | undefined)?.consumers ?? []).length;
    expect(consumers(block)).toBe(consumers(config));
  });

  test.each(envs)("env.%s has its own Worker name", (name, block) => {
    expect(block.name).toMatch(new RegExp(`-${name}$`));
  });
});

test("the jobs Worker's crons match SCHEDULES in every block", () => {
  const worker = configs.find(({ app }) => app === "worker")!.config;
  const crons = (b: Block) => [...((b.triggers as { crons?: string[] })?.crons ?? [])].sort();
  for (const block of [worker, ...Object.values(worker.env ?? {})])
    expect(crons(block)).toEqual(Object.keys(SCHEDULES).sort());
});
