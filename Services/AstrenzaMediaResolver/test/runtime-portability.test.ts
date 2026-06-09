import { timingSafeEqual as nodeTimingSafeEqual } from "node:crypto";
import { encode as encodeJpeg } from "jpeg-js";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { ResolveResult } from "../src/core/schema";
import { createMediaResolverHandler } from "../src/index";
import type { RuntimeAdapterFactory } from "../src/runtime/adapter";
import { createPassThroughImageTransformer } from "../src/runtime/cloudflare-image";
import { InMemoryMetaCache } from "../src/runtime/memory-cache";

type ResolverTestEnv = Env & {
  ASTRENZA_SERVICE_TOKEN: string;
};

type TestSubtleCrypto = SubtleCrypto & {
  timingSafeEqual?: (left: ArrayBuffer, right: ArrayBuffer) => boolean;
};

function compileTimeChecks(): void {
  // @ts-expect-error adapter なしの handler は Cloudflare ExecutionContext 専用にする。
  createMediaResolverHandler<ResolverTestEnv, unknown>();
}

function resolverEnv(): ResolverTestEnv {
  return {
    SERVICE_VERSION: "1",
    DEFAULT_CACHE_TTL_SECONDS: "86400",
    MAX_HTML_BYTES: "1048576",
    MAX_IMAGE_PROBE_BYTES: "131072",
    ASTRENZA_SERVICE_TOKEN: "expected-token",
  } as ResolverTestEnv;
}

function imageRequest(targetUrl: string): Request {
  return new Request(
    `https://media.example.com/v1/image/timeline?url=${encodeURIComponent(
      targetUrl,
    )}`,
    {
      method: "GET",
      headers: {
        Authorization: "Bearer expected-token",
        Accept: "image/avif,image/webp",
      },
    },
  );
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

describe("runtime portability adapters", () => {
  beforeEach(() => {
    installTimingSafeEqualShim();
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("can use pass-through image transformer without Cloudflare cf.image init", async () => {
    const upstreamBody = new ReadableStream<Uint8Array>({
      start(controller) {
        controller.enqueue(new TextEncoder().encode("image-bytes"));
        controller.close();
      },
    });
    const calls: Array<{ input: RequestInfo | URL; init?: RequestInit }> = [];
    const fetchMock = vi.fn<typeof fetch>(async (input, init) => {
      calls.push({ input, init });
      return new Response(upstreamBody, {
        status: 200,
        headers: {
          "Content-Type": "image/png",
          ETag: '"upstream"',
        },
      });
    });
    const worker = createMediaResolverHandler<ResolverTestEnv, unknown>({
      runtimeAdapter: ({ request, env }) => ({
        fetch: fetchMock,
        imageTransformer: createPassThroughImageTransformer(fetchMock),
        serviceOrigin: new URL(request.url).origin,
        limits: {
          cacheTtlSeconds: 86400,
          maxHtmlBytes: Number(env.MAX_HTML_BYTES),
          maxImageProbeBytes: Number(env.MAX_IMAGE_PROBE_BYTES),
        },
        schedule: (task) => void task,
      }),
    });

    const response = await worker.fetch(
      imageRequest("https://cdn.example.com/photo.png"),
      resolverEnv(),
      {},
    );

    expect(response.status).toBe(200);
    expect(response.body).toBe(upstreamBody);
    expect(response.headers.get("Cache-Control")).toBe(
      "public, max-age=86400, stale-while-revalidate=7200, stale-if-error=3600, s-maxage=1209600",
    );
    await expect(response.text()).resolves.toBe("image-bytes");

    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(calls[0]?.input).toBe("https://cdn.example.com/photo.png");
    expect(calls[0]?.init?.redirect).toBe("manual");
    expect(runtimeCloudflareImageOptions(calls[0]?.init)).toBeUndefined();
  });

  it("keeps JSON values in in-memory metadata cache until TTL expires", async () => {
    let now = 1_000;
    const cache = new InMemoryMetaCache({ now: () => now });
    const value: ResolveResult = {
      id: "cached",
      status: "resolved",
      kind: "image",
      url: "https://cdn.example.com/photo.png",
      finalUrl: "https://cdn.example.com/photo.png",
      title: null,
      description: null,
      siteName: null,
      thumbnailStyle: null,
      image: null,
      cacheTtlSeconds: 60,
      warnings: [],
      error: null,
    };

    await cache.put("key", JSON.stringify(value), { expirationTtl: 2 });

    await expect(cache.get("key")).resolves.toBe(JSON.stringify(value));
    now = 2_999;
    await expect(cache.get("key")).resolves.toBe(JSON.stringify(value));
    now = 3_001;
    await expect(cache.get("key")).resolves.toBeNull();
  });

  it("uses custom runtime adapter scheduler without Cloudflare ExecutionContext", async () => {
    const cache = new InMemoryMetaCache();
    const scheduled: Array<Promise<unknown>> = [];
    const png = tinyPng();
    const jpeg = tinyJpeg();
    const fetchMock = vi.fn<typeof fetch>(async (_input, init) => {
      if (runtimeCloudflareImageOptions(init)) {
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
    const runtimeAdapter: RuntimeAdapterFactory<ResolverTestEnv, unknown> = ({
      request,
      env,
    }) => ({
      fetch: fetchMock,
      metaCache: cache,
      imageTransformer: createPassThroughImageTransformer(fetchMock),
      serviceOrigin: new URL(request.url).origin,
      limits: {
        cacheTtlSeconds: Number(env.DEFAULT_CACHE_TTL_SECONDS),
        maxHtmlBytes: Number(env.MAX_HTML_BYTES),
        maxImageProbeBytes: Number(env.MAX_IMAGE_PROBE_BYTES),
      },
      schedule(task) {
        scheduled.push(task);
      },
    });
    const worker = createMediaResolverHandler({ runtimeAdapter });

    const response = await worker.fetch(
      resolveRequest({
        items: [
          {
            id: "direct",
            url: "https://cdn.example.com/photo.png",
            kind: "image",
          },
        ],
      }),
      resolverEnv(),
      { runtime: "self-host-test" },
    );

    expect(response.status).toBe(200);
    const body = (await response.json()) as { results: ResolveResult[] };
    expect(body.results[0]).toMatchObject({
      id: "direct",
      status: "resolved",
      kind: "image",
      error: null,
    });
    expect(scheduled).toHaveLength(1);

    await Promise.all(scheduled);
    const cached = await cache.get(
      await expectedCacheKey("https://cdn.example.com/photo.png", "timeline"),
    );
    expect(cached ? JSON.parse(cached) : null).toMatchObject({
      id: "direct",
      status: "resolved",
    });
    expect(
      fetchMock.mock.calls.every(([_input, init]) => {
        return runtimeCloudflareImageOptions(init) === undefined;
      }),
    ).toBe(true);
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

function runtimeCloudflareImageOptions(
  init: RequestInit | undefined,
): Record<string, unknown> | undefined {
  return (
    init as
      | (RequestInit & { cf?: { image?: Record<string, unknown> } })
      | undefined
  )?.cf?.image;
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

function tinyPng(): Uint8Array {
  return Uint8Array.from(
    Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAIAAAADCAYAAAAAAAAA", "base64"),
  );
}

function bodyBytes(value: Uint8Array): ArrayBuffer {
  const copy = new Uint8Array(value.byteLength);
  copy.set(value);
  return copy.buffer;
}
