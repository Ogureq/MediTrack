// Anonymous-friendly auth: short-lived JWTs (jose, HS256, JWT_SECRET) with
// a refresh flow, plus two clearly-marked P1 stubs (App Attest, Sign in
// with Apple) — see docs/ROADMAP.md Part 4 §1.2 for the full design this
// scaffolds. The relay is stateless: there is no user table anywhere in
// this codebase, so a "user" is entirely defined by the opaque id inside a
// valid JWT `sub` claim, deterministically derived from the client's
// device id (see `deriveUserId` below).

import { SignJWT, jwtVerify, errors as joseErrors, type JWTPayload } from "jose";

export type Tier = "free" | "premium";

export type AuthErrorCode =
  | "expired"
  | "invalid_signature"
  | "malformed"
  | "wrong_token_type"
  | "app_attest_required"
  | "apple_signin_not_implemented";

export class AuthError extends Error {
  readonly code: AuthErrorCode;
  constructor(code: AuthErrorCode, message: string) {
    super(message);
    this.name = "AuthError";
    this.code = code;
  }
}

const ACCESS_TOKEN_TTL_SECONDS = 24 * 60 * 60; // 24h, per docs/ROADMAP.md Part 4 §1.2
const REFRESH_TOKEN_TTL_SECONDS = 30 * 24 * 60 * 60; // 30 days
const JWT_ALGORITHM = "HS256";

export interface AccessTokenClaims {
  sub: string;
  deviceId: string;
  tier: Tier;
}

export interface RefreshTokenClaims {
  sub: string;
  deviceId: string;
  tier: Tier;
}

export interface IssuedTokenPair {
  accessToken: string;
  refreshToken: string;
  accessTokenExpiresAt: string;
  refreshTokenExpiresAt: string;
  tier: Tier;
}

function secretKey(secret: string): Uint8Array {
  return new TextEncoder().encode(secret);
}

function sha256Hex(input: string): Promise<string> {
  return crypto.subtle.digest("SHA-256", new TextEncoder().encode(input)).then((digest) =>
    [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("")
  );
}

/**
 * Derives a stable, opaque internal user id from a client-supplied device
 * id. This P1 scaffold has no persistent user table (the relay is
 * stateless — see docs/ROADMAP.md Part 4 §0), so the "user" the quota
 * ledger and JWT `sub` claim refer to is this deterministic hash: the same
 * device always maps to the same internal id, and the id never contains
 * — and can't be reversed to recover — an Apple identifier or the raw
 * device id, matching the "re-mint your own internal ID" guidance in
 * §1.2 ("Anthropic-facing logs never carry an Apple identifier").
 */
export function deriveUserId(deviceId: string): Promise<string> {
  return sha256Hex(`meditrack-relay:anon:${deviceId}`);
}

export async function issueTokenPair(opts: {
  secret: string;
  userId: string;
  deviceId: string;
  tier?: Tier;
  now?: Date;
}): Promise<IssuedTokenPair> {
  const tier = opts.tier ?? "free";
  const now = opts.now ?? new Date();
  const iat = Math.floor(now.getTime() / 1000);
  const accessExp = iat + ACCESS_TOKEN_TTL_SECONDS;
  const refreshExp = iat + REFRESH_TOKEN_TTL_SECONDS;
  const key = secretKey(opts.secret);

  const accessToken = await new SignJWT({ deviceId: opts.deviceId, tier, type: "access" })
    .setProtectedHeader({ alg: JWT_ALGORITHM })
    .setSubject(opts.userId)
    .setIssuedAt(iat)
    .setExpirationTime(accessExp)
    .sign(key);

  const refreshToken = await new SignJWT({ deviceId: opts.deviceId, tier, type: "refresh" })
    .setProtectedHeader({ alg: JWT_ALGORITHM })
    .setSubject(opts.userId)
    .setIssuedAt(iat)
    .setExpirationTime(refreshExp)
    .sign(key);

  return {
    accessToken,
    refreshToken,
    accessTokenExpiresAt: new Date(accessExp * 1000).toISOString(),
    refreshTokenExpiresAt: new Date(refreshExp * 1000).toISOString(),
    tier
  };
}

async function verifyTyped(
  secret: string,
  token: string,
  expectedType: "access" | "refresh",
  now?: Date
): Promise<JWTPayload & { deviceId: string; tier: Tier; type: string }> {
  let payload: JWTPayload;
  try {
    const result = await jwtVerify(token, secretKey(secret), {
      algorithms: [JWT_ALGORITHM],
      ...(now ? { currentDate: now } : {})
    });
    payload = result.payload;
  } catch (err) {
    if (err instanceof joseErrors.JWTExpired) {
      throw new AuthError("expired", "Token has expired.");
    }
    if (err instanceof joseErrors.JWSSignatureVerificationFailed) {
      throw new AuthError("invalid_signature", "Token signature is invalid.");
    }
    throw new AuthError("malformed", "Token could not be verified.");
  }

  if (payload.type !== expectedType) {
    throw new AuthError("wrong_token_type", `Expected a ${expectedType} token.`);
  }
  if (typeof payload.sub !== "string" || typeof payload.deviceId !== "string" || typeof payload.tier !== "string") {
    throw new AuthError("malformed", "Token is missing required claims.");
  }

  return payload as JWTPayload & { deviceId: string; tier: Tier; type: string };
}

export async function verifyAccessToken(secret: string, token: string, now?: Date): Promise<AccessTokenClaims> {
  const payload = await verifyTyped(secret, token, "access", now);
  return { sub: payload.sub as string, deviceId: payload.deviceId, tier: payload.tier as Tier };
}

export async function verifyRefreshToken(secret: string, token: string, now?: Date): Promise<RefreshTokenClaims> {
  const payload = await verifyTyped(secret, token, "refresh", now);
  return { sub: payload.sub as string, deviceId: payload.deviceId, tier: payload.tier as Tier };
}

/** Verifies a refresh token and mints a fresh access+refresh pair for the same user/device/tier. */
export async function rotateFromRefreshToken(opts: {
  secret: string;
  refreshToken: string;
  now?: Date;
}): Promise<IssuedTokenPair> {
  const claims = await verifyRefreshToken(opts.secret, opts.refreshToken, opts.now);
  return issueTokenPair({
    secret: opts.secret,
    userId: claims.sub,
    deviceId: claims.deviceId,
    tier: claims.tier,
    now: opts.now
  });
}

// ---------------------------------------------------------------------------
// TODO(production requirement, tracked for P2): App Attest verification.
//
// This is a P1 scaffold placeholder ONLY. It checks that a plausibly-shaped
// header/assertion string is present so the anonymous-auth flow is wireable
// end-to-end (client → this endpoint → JWT), but it does NOT verify a real
// Apple App Attest assertion. Without the real verification below, this
// endpoint is a free JWT mint for anyone who can call it — do not take this
// to production as-is.
//
// Production must, per docs/ROADMAP.md Part 4 §1.2:
//   1. Verify the attestation object's certificate chain against Apple's
//      App Attest root CA.
//   2. Verify the assertion's nonce/challenge matches a server-issued,
//      single-use value (requires a short-lived challenge endpoint this
//      scaffold does not yet have).
//   3. Verify the key ID + app ID (team ID + bundle ID) match this app.
//   4. Track and persist the per-key sign counter to detect clone/replay.
// Reference: https://developer.apple.com/documentation/devicecheck
// ---------------------------------------------------------------------------
export function verifyAppAttestPlaceholder(assertionHeader: string | null): boolean {
  return typeof assertionHeader === "string" && assertionHeader.trim().length > 0;
}

// ---------------------------------------------------------------------------
// TODO(P2): Sign in with Apple is not implemented in this P1 scaffold.
//
// Production must verify the Apple identity token (a JWS) against Apple's
// public JWKS (https://appleid.apple.com/auth/keys), check `iss`/`aud`/
// `exp`, and use the token's stable `sub` only to link/merge the anonymous
// device record — never forward Apple's `sub` itself into JWTs, logs, or
// the usage ledger (see `deriveUserId` above and docs/ROADMAP.md Part 4
// §1.2's "re-mint your own internal ID" guidance). This stub exists so the
// call site (`POST /v1/auth/apple`, not yet wired in `src/index.ts`) has a
// documented, typed failure mode to build against.
// ---------------------------------------------------------------------------
export function verifyAppleIdentityToken(_identityToken: string): never {
  throw new AuthError(
    "apple_signin_not_implemented",
    "Sign in with Apple is not implemented in this P1 scaffold."
  );
}

// ---------------------------------------------------------------------------
// Anonymous access token — fixed wire contract (see backend/README.md).
//
// `POST /v1/auth/anonymous` exchanges a client-generated `deviceID` for a
// single 24h JWT. Per the fixed contract, `sub` is the `deviceID` itself
// (not a derived hash — there is no separate "internal user id" concept in
// this contract), and the token carries a `premium` boolean claim decided at
// issuance time (see `verifyAppTransactionPlaceholder` below). This is a
// deliberately separate, simpler token shape from `issueTokenPair`'s
// access/refresh pair above: there is no refresh flow — a client whose token
// has expired just calls `/v1/auth/anonymous` again with the same
// `deviceID`, which is cheap and idempotent since there's no App-Attest gate
// on this endpoint yet (see the GA checklist in README.md). `issueTokenPair`/
// `verifyRefreshToken`/`rotateFromRefreshToken` above are kept for their own
// tested behavior but are no longer wired to any route.
// ---------------------------------------------------------------------------

export const ANONYMOUS_TOKEN_TTL_SECONDS = 24 * 60 * 60; // 86400s — matches the wire contract's expiresInSeconds

export interface AnonymousTokenClaims {
  sub: string;
  premium: boolean;
}

export interface IssuedAnonymousToken {
  token: string;
  expiresInSeconds: number;
}

export async function issueAnonymousToken(opts: {
  secret: string;
  deviceId: string;
  premium: boolean;
  now?: Date;
}): Promise<IssuedAnonymousToken> {
  const now = opts.now ?? new Date();
  const iat = Math.floor(now.getTime() / 1000);
  const exp = iat + ANONYMOUS_TOKEN_TTL_SECONDS;

  const token = await new SignJWT({ premium: opts.premium, type: "anon" })
    .setProtectedHeader({ alg: JWT_ALGORITHM })
    .setSubject(opts.deviceId)
    .setIssuedAt(iat)
    .setExpirationTime(exp)
    .sign(secretKey(opts.secret));

  return { token, expiresInSeconds: ANONYMOUS_TOKEN_TTL_SECONDS };
}

export async function verifyAnonymousToken(secret: string, token: string, now?: Date): Promise<AnonymousTokenClaims> {
  let payload: JWTPayload;
  try {
    const result = await jwtVerify(token, secretKey(secret), {
      algorithms: [JWT_ALGORITHM],
      ...(now ? { currentDate: now } : {})
    });
    payload = result.payload;
  } catch (err) {
    if (err instanceof joseErrors.JWTExpired) {
      throw new AuthError("expired", "Token has expired.");
    }
    if (err instanceof joseErrors.JWSSignatureVerificationFailed) {
      throw new AuthError("invalid_signature", "Token signature is invalid.");
    }
    throw new AuthError("malformed", "Token could not be verified.");
  }

  if (payload.type !== "anon") {
    throw new AuthError("wrong_token_type", "Expected an anonymous access token.");
  }
  if (typeof payload.sub !== "string" || typeof payload.premium !== "boolean") {
    throw new AuthError("malformed", "Token is missing required claims.");
  }

  return { sub: payload.sub, premium: payload.premium };
}

// ---------------------------------------------------------------------------
// TODO(GA requirement — see README.md's GA checklist item (a)): App Store
// transaction verification.
//
// This is a placeholder ONLY, in the same spirit as
// `verifyAppAttestPlaceholder` above. `POST /v1/auth/anonymous` accepts an
// optional `appTransaction` (a base64-encoded, Apple-signed JWS) and is
// *supposed* to verify it against Apple's App Store Server API
// (https://developer.apple.com/documentation/appstoreserverapi) to decide
// whether the device has an active MediTrack Premium subscription. Until
// that verification is implemented, this function does NOT parse or trust
// the value at all — it always returns `false`, regardless of
// `ENFORCE_PREMIUM`.
//
// This is deliberate, not an oversight: faking a "verified" result here
// would let anyone mint a premium-flagged token by sending any non-empty
// string, defeating `ENFORCE_PREMIUM` entirely. Failing closed means that
// with `ENFORCE_PREMIUM=true`, every device gets `premium: false` until real
// verification lands — see README.md for the one-lifetime-free-report
// allowance that keeps "report" partially usable in the meantime, and note
// that App Attest (GA checklist item (b)) matters even more here: without
// it, nothing stops a bad actor from generating a fresh `deviceID` per call
// to keep re-claiming that free report.
// ---------------------------------------------------------------------------
export function verifyAppTransactionPlaceholder(_appTransaction: string | null): boolean {
  return false;
}
