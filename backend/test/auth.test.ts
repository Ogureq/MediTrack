import { describe, expect, it } from "vitest";
import {
  AuthError,
  deriveUserId,
  issueTokenPair,
  rotateFromRefreshToken,
  verifyAccessToken,
  verifyAppAttestPlaceholder,
  verifyAppleIdentityToken,
  verifyRefreshToken
} from "../src/auth";

const SECRET = "test-only-secret-value-not-used-anywhere-real";
const OTHER_SECRET = "a-completely-different-secret-value";

describe("issue / verify round trip", () => {
  it("issues an access+refresh pair whose access token verifies back to the same claims", async () => {
    const now = new Date("2026-07-12T12:00:00.000Z");
    const pair = await issueTokenPair({ secret: SECRET, userId: "user-abc", deviceId: "device-1", now });

    const claims = await verifyAccessToken(SECRET, pair.accessToken, now);
    expect(claims).toEqual({ sub: "user-abc", deviceId: "device-1", tier: "free" });
  });

  it("issues tokens for a given tier and preserves it through verification", async () => {
    const now = new Date("2026-07-12T12:00:00.000Z");
    const pair = await issueTokenPair({ secret: SECRET, userId: "user-abc", deviceId: "device-1", tier: "premium", now });
    expect(pair.tier).toBe("premium");

    const claims = await verifyAccessToken(SECRET, pair.accessToken, now);
    expect(claims.tier).toBe("premium");
  });

  it("sets accessTokenExpiresAt 24h after issuance", async () => {
    const now = new Date("2026-07-12T12:00:00.000Z");
    const pair = await issueTokenPair({ secret: SECRET, userId: "user-abc", deviceId: "device-1", now });
    expect(pair.accessTokenExpiresAt).toBe("2026-07-13T12:00:00.000Z");
  });

  it("rejects an access token presented at the refresh-token verifier", async () => {
    const now = new Date("2026-07-12T12:00:00.000Z");
    const pair = await issueTokenPair({ secret: SECRET, userId: "user-abc", deviceId: "device-1", now });

    await expect(verifyRefreshToken(SECRET, pair.accessToken, now)).rejects.toMatchObject({
      code: "wrong_token_type"
    });
  });
});

describe("expiry rejection", () => {
  it("rejects an access token verified more than 24h after issuance", async () => {
    const issuedAt = new Date("2026-07-12T12:00:00.000Z");
    const pair = await issueTokenPair({ secret: SECRET, userId: "user-abc", deviceId: "device-1", now: issuedAt });

    const justAfterExpiry = new Date("2026-07-13T12:00:01.000Z");
    await expect(verifyAccessToken(SECRET, pair.accessToken, justAfterExpiry)).rejects.toBeInstanceOf(AuthError);
    await expect(verifyAccessToken(SECRET, pair.accessToken, justAfterExpiry)).rejects.toMatchObject({
      code: "expired"
    });
  });

  it("still accepts the token just before expiry", async () => {
    const issuedAt = new Date("2026-07-12T12:00:00.000Z");
    const pair = await issueTokenPair({ secret: SECRET, userId: "user-abc", deviceId: "device-1", now: issuedAt });

    const justBeforeExpiry = new Date("2026-07-13T11:59:59.000Z");
    await expect(verifyAccessToken(SECRET, pair.accessToken, justBeforeExpiry)).resolves.toMatchObject({
      sub: "user-abc"
    });
  });
});

describe("bad signature rejection", () => {
  it("rejects a token verified against the wrong secret", async () => {
    const now = new Date("2026-07-12T12:00:00.000Z");
    const pair = await issueTokenPair({ secret: SECRET, userId: "user-abc", deviceId: "device-1", now });

    await expect(verifyAccessToken(OTHER_SECRET, pair.accessToken, now)).rejects.toMatchObject({
      code: "invalid_signature"
    });
  });

  it("rejects a structurally malformed token", async () => {
    await expect(verifyAccessToken(SECRET, "not-a-jwt", new Date())).rejects.toBeInstanceOf(AuthError);
  });
});

describe("refresh flow", () => {
  it("rotates a valid refresh token into a fresh, independently-valid pair", async () => {
    const issuedAt = new Date("2026-07-12T12:00:00.000Z");
    const original = await issueTokenPair({ secret: SECRET, userId: "user-abc", deviceId: "device-1", now: issuedAt });

    const rotatedAt = new Date("2026-07-12T18:00:00.000Z");
    const rotated = await rotateFromRefreshToken({ secret: SECRET, refreshToken: original.refreshToken, now: rotatedAt });

    expect(rotated.accessToken).not.toBe(original.accessToken);
    const claims = await verifyAccessToken(SECRET, rotated.accessToken, rotatedAt);
    expect(claims).toEqual({ sub: "user-abc", deviceId: "device-1", tier: "free" });
  });

  it("rejects rotation using an expired refresh token", async () => {
    const issuedAt = new Date("2026-07-12T12:00:00.000Z");
    const original = await issueTokenPair({ secret: SECRET, userId: "user-abc", deviceId: "device-1", now: issuedAt });

    const wayLater = new Date(issuedAt.getTime() + 31 * 24 * 60 * 60 * 1000);
    await expect(
      rotateFromRefreshToken({ secret: SECRET, refreshToken: original.refreshToken, now: wayLater })
    ).rejects.toMatchObject({ code: "expired" });
  });
});

describe("deriveUserId", () => {
  it("is deterministic for the same device id", async () => {
    const id1 = await deriveUserId("device-xyz");
    const id2 = await deriveUserId("device-xyz");
    expect(id1).toBe(id2);
  });

  it("differs across device ids", async () => {
    const id1 = await deriveUserId("device-a");
    const id2 = await deriveUserId("device-b");
    expect(id1).not.toBe(id2);
  });

  it("never returns the raw device id verbatim", async () => {
    const deviceId = "device-plainly-visible";
    const derived = await deriveUserId(deviceId);
    expect(derived).not.toContain(deviceId);
    expect(derived).toMatch(/^[0-9a-f]{64}$/);
  });
});

describe("App Attest placeholder (P1 stub)", () => {
  it("accepts any non-empty assertion string", () => {
    expect(verifyAppAttestPlaceholder("some-assertion-bytes")).toBe(true);
  });

  it("rejects a missing or empty assertion", () => {
    expect(verifyAppAttestPlaceholder(null)).toBe(false);
    expect(verifyAppAttestPlaceholder("")).toBe(false);
    expect(verifyAppAttestPlaceholder("   ")).toBe(false);
  });
});

describe("Sign in with Apple stub", () => {
  it("throws a typed not-implemented error", () => {
    expect(() => verifyAppleIdentityToken("some-identity-token")).toThrow(AuthError);

    let caught: unknown;
    try {
      verifyAppleIdentityToken("some-identity-token");
    } catch (err) {
      caught = err;
    }
    expect(caught).toBeInstanceOf(AuthError);
    expect((caught as AuthError).code).toBe("apple_signin_not_implemented");
  });
});
