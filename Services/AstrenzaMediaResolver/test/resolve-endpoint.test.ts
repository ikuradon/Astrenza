import { timingSafeEqual as nodeTimingSafeEqual } from "node:crypto";
import { encode as encodeJpeg } from "jpeg-js";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { ResolveResult } from "../src/core/schema";
import worker from "../src/index";

type ResolverTestEnv = Env & {
  ASTRENZA_SERVICE_TOKEN: string;
  META_CACHE?: KVNamespace;
};

type TestSubtleCrypto = SubtleCrypto & {
  timingSafeEqual?: (left: ArrayBuffer, right: ArrayBuffer) => boolean;
};

type TestExecutionContext = {
  ctx: ExecutionContext;
  waitUntilPromises: Array<Promise<unknown>>;
  waitUntil: ReturnType<typeof vi.fn>;
};

const tinyPngBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAIAAAADCAYAAAAAAAAA";

class FakeMetaCache {
  readonly values = new Map<string, string>();
  readonly ttls = new Map<string, number | undefined>();

  readonly get = vi.fn(async (key: string) => {
    return this.values.get(key) ?? null;
  });

  readonly put = vi.fn(
    async (
      key: string,
      value: string,
      options?: { expirationTtl?: number },
    ) => {
      this.values.set(key, value);
      this.ttls.set(key, options?.expirationTtl);
    },
  );

  asNamespace(): KVNamespace {
    return this as unknown as KVNamespace;
  }
}

function resolverEnv(cache?: FakeMetaCache): ResolverTestEnv {
  return {
    SERVICE_VERSION: "1",
    DEFAULT_CACHE_TTL_SECONDS: "86400",
    MAX_HTML_BYTES: "1048576",
    MAX_IMAGE_PROBE_BYTES: "131072",
    ASTRENZA_SERVICE_TOKEN: "expected-token",
    ...(cache ? { META_CACHE: cache.asNamespace() } : {}),
  } as ResolverTestEnv;
}

function executionContext(): TestExecutionContext {
  const waitUntilPromises: Array<Promise<unknown>> = [];
  const waitUntil = vi.fn((promise: Promise<unknown>) => {
    waitUntilPromises.push(promise);
  });

  return {
    ctx: { waitUntil } as unknown as ExecutionContext,
    waitUntilPromises,
    waitUntil,
  };
}

function resolveRequest(body: unknown): Request {
  return new Request("https://media.example.com/v1/resolve", {
    method: "POST",
    headers: {
      Authorization: "Bearer expected-token",
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
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

describe("resolve endpoint", () => {
  beforeEach(() => {
    installTimingSafeEqualShim();
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("resolves direct image URLs and HTML metadata with optimized URLs", async () => {
    const png = fixtureBytes(tinyPngBase64);
    const jpeg = tinyJpeg();
    const fetchMock = vi.fn<typeof fetch>(async (input, init) => {
      const url = String(input);
      if (cloudflareImageOptions(init)) {
        return new Response(bodyBytes(jpeg), {
          status: 200,
          headers: { "Content-Type": "image/jpeg" },
        });
      }

      if (url === "https://news.example.com/post") {
        return new Response(
          `
            <html>
              <head>
                <meta property="og:title" content="OG title">
                <meta property="og:description" content="OG description">
                <meta property="og:image" content="https://cdn.example.com/cover.png">
              </head>
            </html>
          `,
          {
            status: 200,
            headers: { "Content-Type": "text/html; charset=utf-8" },
          },
        );
      }

      if (init?.method === "HEAD") {
        return new Response(null, { status: 200 });
      }

      return new Response(bodyBytes(png), {
        status: 206,
        headers: { "Content-Type": "image/png" },
      });
    });
    vi.stubGlobal("fetch", fetchMock);

    const response = await worker.fetch(
      resolveRequest({
        imagePreset: "thumb",
        items: [
          {
            id: "direct",
            url: "https://cdn.example.com/photo.png",
            kind: "auto",
          },
          {
            id: "article",
            url: "https://news.example.com/post",
            kind: "auto",
          },
        ],
      }),
      resolverEnv(),
      executionContext().ctx,
    );

    expect(response.status).toBe(200);
    const body = (await response.json()) as { results: ResolveResult[] };
    expect(body.results).toHaveLength(2);
    expect(body.results[0]).toMatchObject({
      id: "direct",
      status: "resolved",
      kind: "image",
      url: "https://cdn.example.com/photo.png",
      finalUrl: "https://cdn.example.com/photo.png",
      title: null,
      description: null,
      image: {
        url: "https://cdn.example.com/photo.png",
        optimizedUrl:
          "https://media.example.com/v1/image/thumb?url=https%3A%2F%2Fcdn.example.com%2Fphoto.png",
        mimeType: "image/png",
        width: 2,
        height: 3,
      },
      error: null,
    });
    expect(body.results[0]?.image?.blurhash).toEqual(expect.any(String));
    expect(body.results[1]).toMatchObject({
      id: "article",
      status: "resolved",
      kind: "html",
      url: "https://news.example.com/post",
      finalUrl: "https://news.example.com/post",
      title: "OG title",
      description: "OG description",
      image: {
        url: "https://cdn.example.com/cover.png",
        optimizedUrl:
          "https://media.example.com/v1/image/thumb?url=https%3A%2F%2Fcdn.example.com%2Fcover.png",
        mimeType: "image/png",
        width: 2,
        height: 3,
      },
      error: null,
    });
    expect(body.results[1]?.image?.blurhash).toEqual(expect.any(String));

    const directHtmlFetches = fetchMock.mock.calls.filter(([input, init]) => {
      const headers = new Headers(init?.headers);
      return (
        String(input) === "https://cdn.example.com/photo.png" &&
        headers.get("Accept")?.includes("text/html")
      );
    });
    expect(directHtmlFetches).toHaveLength(0);
  });

  it("detects extensionless direct image URLs without fetching HTML metadata", async () => {
    const png = fixtureBytes(tinyPngBase64);
    const jpeg = tinyJpeg();
    const fetchMock = vi.fn<typeof fetch>(async (_input, init) => {
      if (cloudflareImageOptions(init)) {
        return new Response(bodyBytes(jpeg), {
          status: 200,
          headers: { "Content-Type": "image/jpeg" },
        });
      }

      if (init?.method === "HEAD") {
        return new Response(null, {
          status: 200,
          headers: { "Content-Type": "image/png" },
        });
      }

      return new Response(bodyBytes(png), {
        status: 206,
        headers: { "Content-Type": "image/png" },
      });
    });
    vi.stubGlobal("fetch", fetchMock);

    const response = await worker.fetch(
      resolveRequest({
        items: [
          {
            id: "extensionless",
            url: "https://cdn.example.com/media/abc123",
            kind: "auto",
          },
        ],
      }),
      resolverEnv(),
      executionContext().ctx,
    );

    expect(response.status).toBe(200);
    const body = (await response.json()) as { results: ResolveResult[] };
    expect(body.results[0]).toMatchObject({
      id: "extensionless",
      status: "resolved",
      kind: "image",
      image: {
        url: "https://cdn.example.com/media/abc123",
        mimeType: "image/png",
        width: 2,
        height: 3,
      },
      error: null,
    });

    const htmlFetches = fetchMock.mock.calls.filter(([_input, init]) => {
      const headers = new Headers(init?.headers);
      return headers.get("Accept")?.includes("text/html");
    });
    expect(htmlFetches).toHaveLength(0);
  });

  it("keeps per-item failures and writes resolved and failed results to optional KV", async () => {
    const cache = new FakeMetaCache();
    const { ctx, waitUntilPromises, waitUntil } = executionContext();
    const png = fixtureBytes(tinyPngBase64);
    const jpeg = tinyJpeg();
    const fetchMock = vi.fn<typeof fetch>(async (input, init) => {
      if (cloudflareImageOptions(init)) {
        return new Response(bodyBytes(jpeg), {
          status: 200,
          headers: { "Content-Type": "image/jpeg" },
        });
      }

      if (String(input) === "https://news.example.com/missing") {
        return new Response("missing", {
          status: 404,
          headers: { "Content-Type": "text/html" },
        });
      }

      if (init?.method === "HEAD") {
        return new Response(null, { status: 200 });
      }

      return new Response(bodyBytes(png), {
        status: 206,
        headers: { "Content-Type": "image/png" },
      });
    });
    vi.stubGlobal("fetch", fetchMock);

    const response = await worker.fetch(
      resolveRequest({
        imagePreset: "timeline",
        items: [
          {
            id: "direct",
            url: "https://cdn.example.com/photo.png",
            kind: "image",
          },
          {
            id: "missing",
            url: "https://news.example.com/missing",
            kind: "html",
          },
        ],
      }),
      resolverEnv(cache),
      ctx,
    );

    expect(response.status).toBe(200);
    const body = (await response.json()) as { results: ResolveResult[] };
    expect(body.results).toMatchObject([
      { id: "direct", status: "resolved", error: null },
      { id: "missing", status: "failed", error: "http_status" },
    ]);
    expect(waitUntil).toHaveBeenCalledTimes(2);
    await Promise.all(waitUntilPromises);

    const resolvedKey = await expectedCacheKey(
      "https://cdn.example.com/photo.png",
      "timeline",
    );
    const failedKey = await expectedCacheKey(
      "https://news.example.com/missing",
      "timeline",
    );

    expect(cache.ttls.get(resolvedKey)).toBe(86400);
    expect(cache.ttls.get(failedKey)).toBe(1800);
    expect(JSON.parse(cache.values.get(resolvedKey) ?? "{}")).toMatchObject({
      id: "direct",
      status: "resolved",
    });
    expect(JSON.parse(cache.values.get(failedKey) ?? "{}")).toMatchObject({
      id: "missing",
      status: "failed",
      error: "http_status",
    });
  });

  it("serves cached resolve results without fetching", async () => {
    const cache = new FakeMetaCache();
    const { ctx, waitUntil } = executionContext();
    const cached: ResolveResult = {
      id: "cached",
      status: "resolved",
      kind: "image",
      url: "https://cdn.example.com/cached.png",
      finalUrl: "https://cdn.example.com/cached.png",
      title: null,
      description: null,
      siteName: null,
      thumbnailStyle: null,
      image: {
        url: "https://cdn.example.com/cached.png",
        optimizedUrl:
          "https://media.example.com/v1/image/thumb?url=https%3A%2F%2Fcdn.example.com%2Fcached.png",
        mimeType: "image/png",
        width: 2,
        height: 3,
        blurhash: "LEHV6nWB2yk8pyo0adR*.7kCMdnj",
      },
      cacheTtlSeconds: 86400,
      warnings: [],
      error: null,
    };
    cache.values.set(
      await expectedCacheKey("https://cdn.example.com/cached.png", "thumb"),
      JSON.stringify(cached),
    );
    const fetchMock = vi.fn<typeof fetch>();
    vi.stubGlobal("fetch", fetchMock);

    const response = await worker.fetch(
      resolveRequest({
        imagePreset: "thumb",
        items: [
          {
            id: "cached",
            url: "https://cdn.example.com/cached.png",
            kind: "auto",
          },
        ],
      }),
      resolverEnv(cache),
      ctx,
    );

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toEqual({ results: [cached] });
    expect(fetchMock).not.toHaveBeenCalled();
    expect(cache.put).not.toHaveBeenCalled();
    expect(waitUntil).not.toHaveBeenCalled();
  });

  it("treats KV read failures as cache misses", async () => {
    const cache = new FakeMetaCache();
    cache.get.mockRejectedValueOnce(new Error("kv down"));
    const { ctx, waitUntilPromises } = executionContext();
    const png = fixtureBytes(tinyPngBase64);
    const jpeg = tinyJpeg();
    const fetchMock = vi.fn<typeof fetch>(async (_input, init) => {
      if (cloudflareImageOptions(init)) {
        return new Response(bodyBytes(jpeg), {
          status: 200,
          headers: { "Content-Type": "image/jpeg" },
        });
      }

      if (init?.method === "HEAD") {
        return new Response(null, { status: 200 });
      }

      return new Response(bodyBytes(png), {
        status: 206,
        headers: { "Content-Type": "image/png" },
      });
    });
    vi.stubGlobal("fetch", fetchMock);

    const response = await worker.fetch(
      resolveRequest({
        items: [
          {
            id: "image",
            url: "https://cdn.example.com/photo.png",
            kind: "image",
          },
        ],
      }),
      resolverEnv(cache),
      ctx,
    );

    expect(response.status).toBe(200);
    const body = (await response.json()) as { results: ResolveResult[] };
    expect(body.results[0]).toMatchObject({
      id: "image",
      status: "resolved",
      error: null,
    });

    await Promise.all(waitUntilPromises);
    expect(cache.put).toHaveBeenCalledTimes(1);
  });

  it("rejects batches over 20 items", async () => {
    const response = await worker.fetch(
      resolveRequest({
        items: Array.from({ length: 21 }, (_, index) => ({
          id: String(index),
          url: `https://example.com/${index}`,
          kind: "auto",
        })),
      }),
      resolverEnv(),
      executionContext().ctx,
    );

    expect(response.status).toBe(400);
    await expect(response.json()).resolves.toEqual({
      error: "invalid_request",
    });
  });

  it("accepts empty resolve batches", async () => {
    const fetchMock = vi.fn<typeof fetch>();
    vi.stubGlobal("fetch", fetchMock);

    const response = await worker.fetch(
      resolveRequest({ items: [] }),
      resolverEnv(),
      executionContext().ctx,
    );

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toEqual({ results: [] });
    expect(fetchMock).not.toHaveBeenCalled();
  });
});

async function expectedCacheKey(
  normalizedUrl: string,
  imagePreset: string,
): Promise<string> {
  const data = new TextEncoder().encode(`${normalizedUrl}\n${imagePreset}`);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return `resolve:v1:${Array.from(new Uint8Array(digest), (byte) =>
    byte.toString(16).padStart(2, "0"),
  ).join("")}`;
}

function tinyJpeg(): Uint8Array {
  const width = 4;
  const height = 4;
  const data = new Uint8Array(width * height * 4);

  for (let index = 0; index < width * height; index += 1) {
    const offset = index * 4;
    data[offset] = (index * 31) % 256;
    data[offset + 1] = 180;
    data[offset + 2] = 255 - index * 9;
    data[offset + 3] = 255;
  }

  return encodeJpeg({ data, width, height }, 80).data;
}

function fixtureBytes(base64: string): Uint8Array {
  return decodeBase64(base64.trim());
}

function decodeBase64(value: string): Uint8Array {
  return Uint8Array.from(Buffer.from(value, "base64"));
}

function bodyBytes(value: Uint8Array): ArrayBuffer {
  const copy = new Uint8Array(value.byteLength);
  copy.set(value);
  return copy.buffer;
}

function cloudflareImageOptions(
  init: RequestInit | undefined,
): Record<string, unknown> | undefined {
  return (
    init as
      | (RequestInit & { cf?: { image?: Record<string, unknown> } })
      | undefined
  )?.cf?.image;
}
