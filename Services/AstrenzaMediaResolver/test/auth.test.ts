import { timingSafeEqual as nodeTimingSafeEqual } from "node:crypto";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { bearerToken, verifyBearerToken } from "../src/core/auth";
import worker from "../src/index";

type ResolverTestEnv = Env & {
  ASTRENZA_SERVICE_TOKEN: string;
};

type TestSubtleCrypto = SubtleCrypto & {
  timingSafeEqual?: (left: ArrayBuffer, right: ArrayBuffer) => boolean;
};

function resolverEnv(): ResolverTestEnv {
  return {
    SERVICE_VERSION: "1",
    ASTRENZA_SERVICE_TOKEN: "expected-token",
  } as ResolverTestEnv;
}

function resolveRequest(init?: RequestInit): Request {
  return new Request("https://media.example.com/v1/resolve", {
    method: "POST",
    body: "not-json",
    ...init,
  });
}

function installTimingSafeEqualShim(): void {
  const subtle = crypto.subtle as TestSubtleCrypto;
  if (subtle.timingSafeEqual) return;

  Object.defineProperty(subtle, "timingSafeEqual", {
    configurable: true,
    value(left: ArrayBuffer, right: ArrayBuffer): boolean {
      return nodeTimingSafeEqual(Buffer.from(left), Buffer.from(right));
    },
  });
}

describe("resolve auth", () => {
  beforeEach(() => {
    installTimingSafeEqualShim();
  });

  it("missing Authorization returns 401 for /v1/resolve", async () => {
    const response = await worker.fetch(
      resolveRequest(),
      resolverEnv(),
      {} as ExecutionContext,
    );

    expect(response.status).toBe(401);
    await expect(response.json()).resolves.toEqual({
      error: "missing_authorization",
    });
  });

  it("invalid bearer returns 403", async () => {
    const response = await worker.fetch(
      resolveRequest({
        headers: { Authorization: "Bearer wrong-token" },
      }),
      resolverEnv(),
      {} as ExecutionContext,
    );

    expect(response.status).toBe(403);
    await expect(response.json()).resolves.toEqual({
      error: "invalid_authorization",
    });
  });

  it("valid bearer reaches route validation", async () => {
    const response = await worker.fetch(
      resolveRequest({
        headers: { Authorization: "Bearer expected-token" },
      }),
      resolverEnv(),
      {} as ExecutionContext,
    );

    expect(response.status).toBe(400);
    await expect(response.json()).resolves.toEqual({
      error: "invalid_json",
    });
  });
});

describe("verifyBearerToken", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("comparison hashes both values before timingSafeEqual", async () => {
    const providedHash = new Uint8Array([1, 2, 3]).buffer;
    const expectedHash = new Uint8Array([4, 5, 6]).buffer;
    const digest = vi
      .fn<SubtleCrypto["digest"]>()
      .mockResolvedValueOnce(providedHash)
      .mockResolvedValueOnce(expectedHash);
    const timingSafeEqual = vi.fn(() => true);

    vi.stubGlobal("crypto", {
      subtle: {
        digest,
        timingSafeEqual,
      },
    });

    const result = await verifyBearerToken(
      new Request("https://media.example.com/v1/resolve", {
        headers: { Authorization: "Bearer provided-token" },
      }),
      "expected-token",
    );

    expect(result).toBe(true);
    expect(digest).toHaveBeenCalledTimes(2);
    expect(digest.mock.calls[0]?.[0]).toBe("SHA-256");
    expect(digest.mock.calls[0]?.[1]).toEqual(
      new TextEncoder().encode("provided-token"),
    );
    expect(digest.mock.calls[1]?.[0]).toBe("SHA-256");
    expect(digest.mock.calls[1]?.[1]).toEqual(
      new TextEncoder().encode("expected-token"),
    );
    expect(timingSafeEqual).toHaveBeenCalledWith(providedHash, expectedHash);
  });
});

describe("bearerToken", () => {
  it("accepts bearer auth scheme case-insensitively", () => {
    const request = new Request("https://media.example.com/v1/resolve", {
      headers: { Authorization: "bearer provided-token" },
    });

    expect(bearerToken(request)).toBe("provided-token");
  });

  it("returns null when the bearer token is blank after trimming", () => {
    const request = new Request("https://media.example.com/v1/resolve", {
      headers: { Authorization: "Bearer    " },
    });

    expect(bearerToken(request)).toBeNull();
  });
});
