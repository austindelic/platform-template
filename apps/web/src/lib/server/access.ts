import { createRemoteJWKSet, jwtVerify, type JWTVerifyGetKey } from "jose";

/**
 * Cloudflare Access sits in front of the web host (infra/cloud/modules/access) and forwards a
 * signed JWT in `Cf-Access-Jwt-Assertion`. hooks.server.ts verifies it again on every request
 * (signature from the team's JWKS, issuer, audience, expiry), so a request that reaches the Worker
 * some other way (workers.dev, a misrouted domain, a missing Access app) is refused. People carry
 * an `email`; service tokens carry a `common_name`.
 */
export type Viewer =
  | { kind: "person"; email: string; subject: string }
  | { kind: "service"; clientId: string; subject: string }
  | { kind: "local"; email: string };

export interface AccessEnv {
  ENVIRONMENT?: string;
  CF_ACCESS_TEAM_DOMAIN?: string;
  CF_ACCESS_AUD?: string;
}

export class AccessError extends Error {
  constructor(
    readonly status: 401 | 403 | 503,
    message: string,
  ) {
    super(message);
    this.name = "AccessError";
  }
}

export const ACCESS_HEADER = "cf-access-jwt-assertion";
export const LOCAL_VIEWER: Viewer = { kind: "local", email: "local developer" };

export function isLocal(env: AccessEnv) {
  return env.ENVIRONMENT === "local";
}

/** `https://<team>.cloudflareaccess.com` with no path; anything else is a configuration error. */
export function teamDomain(value: string | undefined) {
  const raw = value?.trim() ?? "";
  if (!raw) return null;
  try {
    const url = new URL(raw.includes("://") ? raw : `https://${raw}`);
    if (url.protocol !== "https:" || url.username || url.password || url.search || url.hash)
      return null;
    if (url.pathname !== "/" && url.pathname !== "") return null;
    return url.origin;
  } catch {
    return null;
  }
}

export function audiences(value: string | undefined) {
  return (value ?? "")
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);
}

const keySets = new Map<string, JWTVerifyGetKey>();
function remoteKeys(issuer: string) {
  let keys = keySets.get(issuer);
  if (!keys) {
    keys = createRemoteJWKSet(new URL("/cdn-cgi/access/certs", issuer), {
      cooldownDuration: 30_000,
      cacheMaxAge: 10 * 60_000,
    });
    keySets.set(issuer, keys);
  }
  return keys;
}

/**
 * Resolves the viewer for a request or throws `AccessError`. Only `ENVIRONMENT=local` skips the
 * check; a hosted environment without a team domain and audience fails closed with 503.
 */
export async function verifyAccess(
  headers: Headers,
  env: AccessEnv,
  options: { keys?: JWTVerifyGetKey } = {},
): Promise<Viewer> {
  if (isLocal(env)) return LOCAL_VIEWER;
  const issuer = teamDomain(env.CF_ACCESS_TEAM_DOMAIN);
  const audience = audiences(env.CF_ACCESS_AUD);
  if (!issuer || !audience.length)
    throw new AccessError(503, "Cloudflare Access is not configured for this environment.");
  const token = headers.get(ACCESS_HEADER)?.trim();
  if (!token) throw new AccessError(401, "Sign in through Cloudflare Access.");
  let payload;
  try {
    ({ payload } = await jwtVerify(token, options.keys ?? remoteKeys(issuer), {
      issuer,
      audience,
      algorithms: ["RS256"],
      clockTolerance: 30,
      requiredClaims: ["exp", "iat"],
    }));
  } catch {
    throw new AccessError(403, "This Cloudflare Access session is not valid here.");
  }
  const subject = typeof payload.sub === "string" ? payload.sub : "";
  if (typeof payload.email === "string" && payload.email)
    return { kind: "person", email: payload.email, subject };
  if (typeof payload.common_name === "string" && payload.common_name)
    return { kind: "service", clientId: payload.common_name, subject };
  throw new AccessError(403, "This Cloudflare Access session has no identity.");
}

export function viewerLabel(viewer: Viewer) {
  if (viewer.kind === "service") return `service token ${viewer.clientId}`;
  return viewer.email;
}
