/**
 * Turns this template into a new project: renames the identifiers and shifts the local ports
 * listed in template.json, sets the CI runner, and records where it came from in
 * .template-origin.json. It never pushes, creates remote repos or touches cloud accounts.
 *
 * In a repo made with GitHub's "Use this template" button (needs a clean working tree):
 *
 *   bun scripts/create-repo.ts --slug acme-portal --in-place
 *
 * Or copy a checkout of the template into a new folder, then `git init -b main` there:
 *
 *   bun scripts/create-repo.ts --slug acme-portal --dest ../acme-portal
 *
 * Options: --title "Acme portal" (default: from the slug), --port-offset auto|N (default auto:
 * the first multiple of 10 whose ports are free and unused by sibling repos), --runner
 * github|blacksmith (default github), --scan-dir DIR (repeatable; folders whose repos' ports to
 * avoid, default the parent folders of the template and the destination), --dry-run.
 *
 * It exits non-zero if a template identifier or port survives. The tracked files in template.json's
 * exclude list (template.json, this script, CONTRIBUTING.md, SECURITY.md, the README banner)
 * are not carried over.
 */
import { execFileSync } from "node:child_process";
import {
  chmodSync,
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { createConnection } from "node:net";
import { basename, dirname, join, resolve } from "node:path";
import { parseArgs } from "node:util";

type Manifest = {
  version?: number;
  replace: Record<string, string>;
  ports: Record<string, number>;
  exclude: string[];
  text_extensions: string[];
};

const LOCK_FILES = new Set(["bun.lock", ".terraform.lock.hcl"]);
const BLACKSMITH = "blacksmith-2vcpu-ubuntu-2404";
/** README sections about the template itself, dropped from new projects. */
const TEMPLATE_ONLY = /<!-- template-only:start -->[\s\S]*?<!-- template-only:end -->\n+/g;

function fail(message: string): never {
  console.error(message);
  process.exit(1);
}

const { values: args } = parseArgs({
  options: {
    slug: { type: "string" },
    dest: { type: "string" },
    "in-place": { type: "boolean", default: false },
    title: { type: "string" },
    template: { type: "string" },
    "port-offset": { type: "string", default: "auto" },
    runner: { type: "string", default: "github" },
    "scan-dir": { type: "string", multiple: true },
    "dry-run": { type: "boolean", default: false },
    help: { type: "boolean", short: "h", default: false },
  },
});

if (args.help) {
  console.log(
    "Usage: bun scripts/create-repo.ts --slug <slug> (--in-place | --dest <dir>) [--title <title>]\n" +
      "         [--port-offset auto|N] [--runner github|blacksmith] [--scan-dir <dir>]... [--dry-run]",
  );
  process.exit(0);
}

const slug = args.slug ?? fail("--slug is required, e.g. --slug acme-portal.");
if (!/^[a-z][a-z0-9-]*[a-z0-9]$/.test(slug)) {
  fail("--slug must be lower-case letters, digits and hyphens, starting with a letter.");
}
if (args["in-place"] === Boolean(args.dest)) fail("Pass exactly one of --in-place or --dest.");
const runner = args.runner;
if (runner !== "github" && runner !== "blacksmith") fail("--runner must be github or blacksmith.");

const expand = (p: string) => resolve(p.replace(/^~(?=$|\/)/, process.env.HOME ?? "~"));
const template = expand(args.template ?? join(import.meta.dirname, ".."));
const inPlace = args["in-place"];
const dest = inPlace ? template : expand(args.dest!);
const manifestPath = join(template, "template.json");
if (!existsSync(manifestPath)) {
  fail(`${manifestPath} not found: this checkout has already been turned into a project.`);
}
const manifest = JSON.parse(readFileSync(manifestPath, "utf8")) as Manifest;
if (!inPlace && existsSync(dest) && readdirSync(dest).length > 0) {
  fail(`${dest} exists and is not empty.`);
}

const git = (gitArgs: string[], cwd: string) =>
  execFileSync("git", gitArgs, { cwd, encoding: "utf8" });

function templateFiles(): string[] {
  const out = git(["ls-files", "-z", "--cached", "--others", "--exclude-standard"], template);
  const excludes = manifest.exclude;
  return out
    .split("\0")
    .filter(Boolean)
    .filter((rel) => {
      const parts = rel.split("/");
      return !excludes.some((e) => rel === e || rel.startsWith(`${e}/`) || parts.includes(e));
    })
    .filter((rel) => existsSync(join(template, rel)) && statSync(join(template, rel)).isFile())
    .sort();
}

function isText(rel: string): boolean {
  const name = basename(rel);
  return (
    LOCK_FILES.has(name) ||
    name === "CODEOWNERS" ||
    manifest.text_extensions.some((ext) => name.endsWith(ext))
  );
}

function setRunner(text: string): string {
  const label = runner === "blacksmith" ? BLACKSMITH : "ubuntu-24.04";
  return text.replace(
    /(runs-on:\s*)(?:blacksmith-\d+vcpu-ubuntu-2404|ubuntu-24\.04)/g,
    `$1${label}`,
  );
}

function portInUse(port: number): Promise<boolean> {
  return new Promise((done) => {
    const socket = createConnection({ host: "127.0.0.1", port });
    const finish = (used: boolean) => {
      socket.destroy();
      done(used);
    };
    socket.setTimeout(200, () => finish(false));
    socket.once("connect", () => finish(true));
    socket.once("error", () => finish(false));
  });
}

const subdirs = (dir: string) => {
  try {
    return readdirSync(dir, { withFileTypes: true })
      .filter((d) => d.isDirectory() && !d.name.startsWith(".") && d.name !== "node_modules")
      .map((d) => join(dir, d.name));
  } catch {
    return [];
  }
};

/** Ports that other local repos publish or serve on, so two projects can run side by side. */
function portsClaimedElsewhere(): Set<number> {
  const claimed = new Set<number>();
  const pattern = /(?:127\.0\.0\.1:|--port[ =]|"port":\s*|localhost:)(\d{4,5})/g;
  const roots = args["scan-dir"]?.map(expand) ?? [dirname(template), dirname(dest)];
  const repos = new Set(roots.flatMap((root) => subdirs(root).flatMap((d) => [d, ...subdirs(d)])));
  repos.delete(template);
  repos.delete(dest);
  for (const repo of repos) {
    const files = [
      ...subdirs(join(repo, "apps")).map((app) => join(app, "package.json")),
      ...(existsSync(join(repo, "infra/local"))
        ? readdirSync(join(repo, "infra/local"))
            .filter((f) => f.endsWith(".yml"))
            .map((f) => join(repo, "infra/local", f))
        : []),
    ];
    for (const file of files) {
      try {
        for (const m of readFileSync(file, "utf8").matchAll(pattern)) claimed.add(Number(m[1]));
      } catch {
        // Missing or unreadable files claim nothing.
      }
    }
  }
  return claimed;
}

async function pickOffset(): Promise<number> {
  if (args["port-offset"] !== "auto") return Number.parseInt(args["port-offset"]!, 10);
  const claimed = portsClaimedElsewhere();
  for (let offset = 10; offset < 400; offset += 10) {
    const ports = Object.values(manifest.ports).map((p) => p + offset);
    if (ports.some((p) => p >= 65535 || claimed.has(p))) continue;
    const used = await Promise.all(ports.map(portInUse));
    if (!used.includes(true)) return offset;
  }
  fail("No free port offset found; pass --port-offset.");
}

const escape = (s: string) => s.replace(/[.*+?^${}()|[\]\\/]/g, "\\$&");
const title = args.title ?? slug.replaceAll("-", " ").replace(/^./, (c) => c.toUpperCase());
const fill: Record<string, string> = { slug, slug_underscore: slug.replaceAll("-", "_"), title };
const replace = Object.fromEntries(
  Object.entries(manifest.replace).map(([k, v]) => [
    k,
    v.replace(/\{(\w+)\}/g, (_, key: string) => fill[key] ?? `{${key}}`),
  ]),
);
const offset = await pickOffset();
const ports = Object.fromEntries(
  Object.values(manifest.ports).map((p) => [String(p), String(p + offset)]),
);
const portRe = new RegExp(`(?<!\\d)(${Object.keys(ports).map(escape).join("|")})(?!\\d)`, "g");
const identRe = new RegExp(
  Object.keys(replace)
    .sort((a, b) => b.length - a.length)
    .map(escape)
    .join("|"),
  "g",
);

const commit = git(["rev-parse", "HEAD"], template).trim();
const dirty = git(["status", "--porcelain"], template).trim() !== "";
const branch = git(["rev-parse", "--abbrev-ref", "HEAD"], template).trim();
if (inPlace && dirty)
  fail("Commit or stash your changes first, so the rewrite can be reviewed and undone.");
const files = templateFiles();

console.log(
  `Template ${template} @ ${commit.slice(0, 12)} (${branch}${dirty ? ", uncommitted changes included" : ""})`,
);
console.log(`${files.length} files -> ${inPlace ? `${dest} (in place)` : dest}`);
console.log(
  `Ports: ${Object.entries(manifest.ports)
    .map(([k, p]) => `${k} ${p + offset}`)
    .join(", ")}`,
);
console.log(`CI runners: ${runner}`);
if (args["dry-run"]) process.exit(0);

for (const rel of files) {
  const src = join(template, rel);
  const out = join(dest, rel);
  mkdirSync(dirname(out), { recursive: true });
  if (isText(rel)) {
    let text = readFileSync(src, "utf8").replace(identRe, (m) => replace[m]!);
    // Lock hashes can contain port-like digits.
    if (!LOCK_FILES.has(basename(rel))) text = text.replace(portRe, (m) => ports[m]!);
    if (rel.startsWith(".github/workflows/")) text = setRunner(text);
    if (rel === "README.md") text = text.replace(TEMPLATE_ONLY, "").replace(/\n+$/, "\n");
    writeFileSync(out, text);
  } else if (!inPlace) {
    writeFileSync(out, readFileSync(src));
  }
  chmodSync(out, statSync(src).mode);
}

const origin = {
  template: "platform-template",
  template_version: manifest.version,
  template_commit: commit,
  template_branch: branch,
  template_dirty: dirty,
  created: new Date().toLocaleDateString("en-CA"), // YYYY-MM-DD in local time
  slug,
  port_offset: offset,
  runner,
  replace,
};
writeFileSync(join(dest, ".template-origin.json"), `${JSON.stringify(origin, null, 2)}\n`);

const leftovers = files.filter((rel) => {
  if (!isText(rel) || LOCK_FILES.has(basename(rel))) return false;
  const text = readFileSync(join(dest, rel), "utf8");
  portRe.lastIndex = 0;
  return Object.keys(replace).some((k) => text.includes(k)) || (offset !== 0 && portRe.test(text));
});

if (inPlace) {
  // Template-only files (template.json, this script, contributor docs, README banner) are
  // the tracked entries of the exclude list. Untracked entries such as node_modules stay.
  const tracked = git(["ls-files", "-z", "--", ...manifest.exclude], template).split("\0");
  const templateOnly = (rel: string) =>
    manifest.exclude.some((e) => rel === e || rel.startsWith(`${e}/`));
  for (const rel of tracked.filter(templateOnly)) {
    rmSync(join(template, rel));
    const dir = dirname(join(template, rel));
    if (dir !== template && readdirSync(dir).length === 0) rmSync(dir, { recursive: true });
  }
  console.log("Rewritten in place. Review with `git diff`, then commit.");
} else {
  git(["init", "-q", "-b", "main"], dest);
  console.log("Created. git initialised on main (nothing committed).");
}
if (leftovers.length > 0) {
  fail(`WARNING: template identifiers or ports remain in: ${leftovers.join(", ")}`);
}
