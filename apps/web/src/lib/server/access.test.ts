import { exportJWK, generateKeyPair, SignJWT, createLocalJWKSet, type JWK } from "jose";
import { beforeAll, expect, test } from "vitest";
import { AccessError, audiences, teamDomain, verifyAccess, viewerLabel } from "./access";

const issuer = "https://example-team.cloudflareaccess.com";
const aud = "web-aud-0000000000000000000000000000000000000000000000000000000000";
const env = { ENVIRONMENT: "production", CF_ACCESS_TEAM_DOMAIN: issuer, CF_ACCESS_AUD: aud };
let keys: ReturnType<typeof createLocalJWKSet>;
let privateKey: CryptoKey;
let otherKey: CryptoKey;

beforeAll(async () => {
  const pair = await generateKeyPair("RS256");
  privateKey = pair.privateKey;
  otherKey = (await generateKeyPair("RS256")).privateKey;
  const jwk: JWK = { ...(await exportJWK(pair.publicKey)), kid: "test-key", alg: "RS256" };
  keys = createLocalJWKSet({ keys: [jwk] });
});

function token(
  claims: Record<string, unknown>,
  options: { key?: CryptoKey; exp?: string; iss?: string; aud?: string } = {},
) {
  return new SignJWT({ type: "app", ...claims })
    .setProtectedHeader({ alg: "RS256", kid: "test-key" })
    .setIssuer(options.iss ?? issuer)
    .setAudience(options.aud ?? aud)
    .setSubject("fictional-subject")
    .setIssuedAt()
    .setExpirationTime(options.exp ?? "5m")
    .sign(options.key ?? privateKey);
}
const headers = (jwt: string) => new Headers({ "cf-access-jwt-assertion": jwt });
async function refusal(promise: Promise<unknown>) {
  const error = await promise.then(
    () => null,
    (cause: unknown) => cause,
  );
  expect(error).toBeInstanceOf(AccessError);
  return (error as AccessError).status;
}

test("a valid Access JWT for a person yields their email", async () => {
  const viewer = await verifyAccess(headers(await token({ email: "editor@example.test" })), env, {
    keys,
  });
  expect(viewer).toEqual({
    kind: "person",
    email: "editor@example.test",
    subject: "fictional-subject",
  });
  expect(viewerLabel(viewer)).toBe("editor@example.test");
});

test("a service token JWT (MCP clients) is identified by its client id", async () => {
  const viewer = await verifyAccess(
    headers(await token({ common_name: "fictional.access" })),
    env,
    { keys },
  );
  expect(viewer).toMatchObject({ kind: "service", clientId: "fictional.access" });
});

test("missing, forged, expired, foreign and misaddressed tokens are refused", async () => {
  expect(await refusal(verifyAccess(new Headers(), env, { keys }))).toBe(401);
  expect(await refusal(verifyAccess(headers("not-a-jwt"), env, { keys }))).toBe(403);
  expect(
    await refusal(
      verifyAccess(headers(await token({ email: "a@example.test" }, { key: otherKey })), env, {
        keys,
      }),
    ),
  ).toBe(403);
  expect(
    await refusal(
      verifyAccess(headers(await token({ email: "a@example.test" }, { exp: "-5m" })), env, {
        keys,
      }),
    ),
  ).toBe(403);
  expect(
    await refusal(
      verifyAccess(
        headers(
          await token({ email: "a@example.test" }, { iss: "https://other.cloudflareaccess.com" }),
        ),
        env,
        { keys },
      ),
    ),
  ).toBe(403);
  expect(
    await refusal(
      verifyAccess(headers(await token({ email: "a@example.test" }, { aud: "another-app" })), env, {
        keys,
      }),
    ),
  ).toBe(403);
  // A valid signature without an identity is not enough.
  expect(await refusal(verifyAccess(headers(await token({})), env, { keys }))).toBe(403);
});

test("HS256 and unsigned tokens are refused even with a matching payload", async () => {
  const secret = new TextEncoder().encode("x".repeat(32));
  const hs = await new SignJWT({ email: "a@example.test" })
    .setProtectedHeader({ alg: "HS256" })
    .setIssuer(issuer)
    .setAudience(aud)
    .setIssuedAt()
    .setExpirationTime("5m")
    .sign(secret);
  expect(await refusal(verifyAccess(headers(hs), env, { keys }))).toBe(403);
  const [, body] = (await token({ email: "a@example.test" })).split(".");
  const none = `${btoa(JSON.stringify({ alg: "none" })).replace(/=+$/, "")}.${body}.`;
  expect(await refusal(verifyAccess(headers(none), env, { keys }))).toBe(403);
});

test("only ENVIRONMENT=local bypasses Access; hosted environments fail closed without config", async () => {
  expect(await verifyAccess(new Headers(), { ENVIRONMENT: "local" })).toMatchObject({
    kind: "local",
  });
  expect(await refusal(verifyAccess(new Headers(), { ENVIRONMENT: "staging" }))).toBe(503);
  expect(await refusal(verifyAccess(new Headers(), {}))).toBe(503);
  expect(
    await refusal(
      verifyAccess(new Headers(), { CF_ACCESS_TEAM_DOMAIN: issuer, CF_ACCESS_AUD: " " }),
    ),
  ).toBe(503);
});

test("several audiences are accepted, so a second Access app can front /mcp", async () => {
  const viewer = await verifyAccess(
    headers(await token({ email: "a@example.test" }, { aud: "mcp-aud" })),
    { ...env, CF_ACCESS_AUD: `${aud}, mcp-aud` },
    { keys },
  );
  expect(viewer.kind).toBe("person");
  expect(audiences(" a, ,b ")).toEqual(["a", "b"]);
});

test("team domains must be bare HTTPS origins", () => {
  expect(teamDomain("example-team.cloudflareaccess.com")).toBe(
    "https://example-team.cloudflareaccess.com",
  );
  expect(teamDomain("https://example-team.cloudflareaccess.com/")).toBe(
    "https://example-team.cloudflareaccess.com",
  );
  expect(teamDomain("http://example-team.cloudflareaccess.com")).toBeNull();
  expect(teamDomain("https://example-team.cloudflareaccess.com/cdn-cgi")).toBeNull();
  expect(teamDomain("https://user:pass@example-team.cloudflareaccess.com")).toBeNull();
  expect(teamDomain("")).toBeNull();
});
