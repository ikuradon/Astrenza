import { timingSafeEqual as nodeTimingSafeEqual } from "node:crypto";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import { imagePresets } from "../src/runtime/cloudflare-image";

type ResolverTestEnv = Env & {
  ASTRENZA_SERVICE_TOKEN: string;
};

type TestSubtleCrypto = SubtleCrypto & {
  timingSafeEqual?: (left: ArrayBuffer, right: ArrayBuffer) => boolean;
};

function resolverEnv(): ResolverTestEnv {
  return {
    SERVICE_VERSION: "1",
    DEFAULT_CACHE_TTL_SECONDS: "86400",
    MAX_HTML_BYTES: "1048576",
    MAX_IMAGE_PROBE_BYTES: "131072",
    ASTRENZA_SERVICE_TOKEN: "expected-token",
  } as ResolverTestEnv;
}

function executionContext(): ExecutionContext {
  return {
    waitUntil: vi.fn(),
  } as unknown as ExecutionContext;
}

function imageRequest(
  preset: string,
  targetUrl: string,
  init: RequestInit = {},
): Request {
  return new Request(
    `https://media.example.com/v1/image/${preset}?url=${encodeURIComponent(
      targetUrl,
    )}`,
    {
      method: "GET",
      headers: { Authorization: "Bearer expected-token" },
      ...init,
    },
  );
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

describe("image endpoint", () => {
  beforeEach(() => {
    installTimingSafeEqualShim();
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("exports the Cloudflare image presets", () => {
    expect(imagePresets).toEqual({
      timeline: { width: 900, quality: 72, fit: "scale-down" },
      thumb: { width: 360, quality: 68, fit: "scale-down" },
      "blurhash-source": {
        width: 32,
        height: 32,
        quality: 60,
        fit: "scale-down",
        format: "jpeg",
      },
    });
  });

  it("streams transformed images with negotiated AVIF and only safe upstream headers", async () => {
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
    vi.stubGlobal("fetch", fetchMock);

    const response = await worker.fetch(
      imageRequest("timeline", "https://cdn.example.com/photo.png", {
        headers: {
          Authorization: "Bearer expected-token",
          Accept: "image/avif,image/webp",
          "Accept-Language": "ja",
          "If-None-Match": '"client"',
          "If-Modified-Since": "Tue, 09 Jun 2026 00:00:00 GMT",
          "X-Forward-Me": "no",
        },
      }),
      resolverEnv(),
      executionContext(),
    );

    expect(response.status).toBe(200);
    expect(response.body).toBe(upstreamBody);
    expect(response.headers.get("Cache-Control")).toBe(
      "public, max-age=86400, stale-while-revalidate=7200, stale-if-error=3600, s-maxage=1209600",
    );
    expect(response.headers.get("Vary")).toBe("Accept");
    await expect(response.text()).resolves.toBe("image-bytes");

    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(calls[0]?.input).toBe("https://cdn.example.com/photo.png");
    expect(calls[0]?.init?.redirect).toBe("manual");
    expect(cloudflareImageOptions(calls[0]?.init)).toEqual({
      width: 900,
      quality: 72,
      fit: "scale-down",
      format: "avif",
    });

    const headers = new Headers(calls[0]?.init?.headers);
    expect(headers.get("Accept")).toBe("image/avif,image/webp");
    expect(headers.get("Accept-Language")).toBe("ja");
    expect(headers.get("If-None-Match")).toBe('"client"');
    expect(headers.get("If-Modified-Since")).toBe(
      "Tue, 09 Jun 2026 00:00:00 GMT",
    );
    expect(headers.get("Authorization")).toBeNull();
    expect(headers.get("X-Forward-Me")).toBeNull();
  });

  it("always uses JPEG for blurhash-source even when the client accepts AVIF", async () => {
    const fetchMock = vi.fn<typeof fetch>(async () => {
      return new Response("jpeg", {
        status: 200,
        headers: { "Content-Type": "image/jpeg" },
      });
    });
    vi.stubGlobal("fetch", fetchMock);

    const response = await worker.fetch(
      imageRequest("blurhash-source", "https://cdn.example.com/photo.png", {
        headers: {
          Authorization: "Bearer expected-token",
          Accept: "image/avif,image/webp",
        },
      }),
      resolverEnv(),
      executionContext(),
    );

    expect(response.status).toBe(200);
    expect(cloudflareImageOptions(fetchMock.mock.calls[0]?.[1])).toEqual({
      width: 32,
      height: 32,
      quality: 60,
      fit: "scale-down",
      format: "jpeg",
    });
  });

  it("rejects unknown presets before fetching", async () => {
    const fetchMock = vi.fn<typeof fetch>();
    vi.stubGlobal("fetch", fetchMock);

    const response = await worker.fetch(
      imageRequest("poster", "https://cdn.example.com/photo.png"),
      resolverEnv(),
      executionContext(),
    );

    expect(response.status).toBe(400);
    await expect(response.json()).resolves.toEqual({
      error: "invalid_image_preset",
    });
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("rejects recursive image proxy URLs", async () => {
    const fetchMock = vi.fn<typeof fetch>();
    vi.stubGlobal("fetch", fetchMock);

    const response = await worker.fetch(
      imageRequest(
        "timeline",
        "https://media.example.com/v1/image/thumb?url=https%3A%2F%2Fcdn.example.com%2Fphoto.png",
      ),
      resolverEnv(),
      executionContext(),
    );

    expect(response.status).toBe(400);
    await expect(response.json()).resolves.toEqual({
      error: "blocked_recursive_request",
    });
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("validates redirect locations before following", async () => {
    const fetchMock = vi.fn<typeof fetch>(async () => {
      return new Response(null, {
        status: 302,
        headers: { Location: "http://127.0.0.1/private.png" },
      });
    });
    vi.stubGlobal("fetch", fetchMock);

    const response = await worker.fetch(
      imageRequest("timeline", "https://cdn.example.com/redirect.png"),
      resolverEnv(),
      executionContext(),
    );

    expect(response.status).toBe(400);
    await expect(response.json()).resolves.toEqual({
      error: "unsafe_redirect",
    });
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it("returns 502 when the upstream image fetch rejects", async () => {
    const fetchMock = vi.fn<typeof fetch>(async () => {
      throw new Error("dns failure");
    });
    vi.stubGlobal("fetch", fetchMock);

    const response = await worker.fetch(
      imageRequest("timeline", "https://cdn.example.com/photo.png"),
      resolverEnv(),
      executionContext(),
    );

    expect(response.status).toBe(502);
    await expect(response.json()).resolves.toEqual({
      error: "upstream_fetch_failed",
    });
  });

  it("does not long-cache upstream error responses", async () => {
    const fetchMock = vi.fn<typeof fetch>(async () => {
      return new Response("missing", {
        status: 404,
        headers: { "Content-Type": "text/plain" },
      });
    });
    vi.stubGlobal("fetch", fetchMock);

    const response = await worker.fetch(
      imageRequest("timeline", "https://cdn.example.com/missing.png"),
      resolverEnv(),
      executionContext(),
    );

    expect(response.status).toBe(404);
    expect(response.headers.get("Cache-Control")).toBe("no-store");
    expect(response.headers.get("Vary")).toBe("Accept");
    await expect(response.text()).resolves.toBe("missing");
  });

  it("rejects successful non-image upstream responses", async () => {
    const fetchMock = vi.fn<typeof fetch>(async () => {
      return new Response("<html></html>", {
        status: 200,
        headers: { "Content-Type": "text/html; charset=utf-8" },
      });
    });
    vi.stubGlobal("fetch", fetchMock);

    const response = await worker.fetch(
      imageRequest("timeline", "https://cdn.example.com/not-image"),
      resolverEnv(),
      executionContext(),
    );

    expect(response.status).toBe(502);
    await expect(response.json()).resolves.toEqual({
      error: "upstream_non_image",
    });
  });
});

function cloudflareImageOptions(
  init: RequestInit | undefined,
): Record<string, unknown> | undefined {
  return (
    init as
      | (RequestInit & { cf?: { image?: Record<string, unknown> } })
      | undefined
  )?.cf?.image;
}
