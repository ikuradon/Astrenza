import { decode as decodeBlurHash, isBlurhashValid } from "blurhash";
import { encode as encodeJpeg } from "jpeg-js";
import { describe, expect, it, vi } from "vitest";
import {
  BLURHASH_MAX_JPEG_BYTES,
  generateBlurHash,
} from "../src/core/blurhash";

describe("generateBlurHash", () => {
  it("fetches Cloudflare transformed JPEG and returns a decodable BlurHash", async () => {
    const jpeg = tinyJpeg();
    const calls: Array<{ input: RequestInfo | URL; init?: RequestInit }> = [];
    const fetchMock = vi.fn<typeof fetch>(async (input, init) => {
      calls.push({ input, init });
      return new Response(bodyBytes(jpeg), {
        status: 200,
        headers: { "Content-Type": "image/jpeg" },
      });
    });

    const result = await generateBlurHash("https://cdn.example.com/cover.png", {
      fetch: fetchMock,
    });

    expect(result.warnings).toEqual([]);
    expect(result.blurhash).not.toBeNull();
    expect(isBlurhashValid(result.blurhash ?? "")).toEqual({ result: true });
    expect(decodeBlurHash(result.blurhash ?? "", 4, 4)).toHaveLength(64);
    expect(calls[0]?.input).toBe("https://cdn.example.com/cover.png");
    expect(cloudflareImageOptions(calls[0]?.init)).toEqual({
      width: 32,
      height: 32,
      fit: "scale-down",
      format: "jpeg",
      quality: 60,
    });
    expect(calls[0]?.init?.redirect).toBe("manual");
  });

  it("validates redirect targets before following", async () => {
    const fetchMock = vi.fn<typeof fetch>(async () => {
      return new Response(null, {
        status: 302,
        headers: { Location: "http://127.0.0.1/private.jpg" },
      });
    });

    await expect(
      generateBlurHash("https://cdn.example.com/redirect.jpg", {
        fetch: fetchMock,
      }),
    ).resolves.toEqual({
      blurhash: null,
      warnings: ["blurhash_failed"],
    });
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it("cancels transformed JPEG bodies that exceed the byte limit", async () => {
    let cancelled = false;
    const body = new ReadableStream<Uint8Array>({
      pull(controller) {
        controller.enqueue(new Uint8Array(BLURHASH_MAX_JPEG_BYTES + 1));
      },
      cancel() {
        cancelled = true;
      },
    });
    const fetchMock = vi.fn<typeof fetch>(async () => {
      return new Response(body, {
        status: 200,
        headers: { "Content-Type": "image/jpeg" },
      });
    });

    await expect(
      generateBlurHash("https://cdn.example.com/huge.jpg", {
        fetch: fetchMock,
      }),
    ).resolves.toEqual({
      blurhash: null,
      warnings: ["blurhash_failed"],
    });
    expect(cancelled).toBe(true);
  });

  it("returns blurhash_failed when the transform fetch fails", async () => {
    const fetchMock = vi.fn<typeof fetch>(async () => {
      return new Response("bad gateway", { status: 502 });
    });

    await expect(
      generateBlurHash("https://cdn.example.com/cover.png", {
        fetch: fetchMock,
      }),
    ).resolves.toEqual({
      blurhash: null,
      warnings: ["blurhash_failed"],
    });
  });

  it("returns blurhash_decode_failed when JPEG decode fails", async () => {
    const fetchMock = vi.fn<typeof fetch>(async () => {
      return new Response(bodyBytes(new Uint8Array([1, 2, 3])), {
        status: 200,
        headers: { "Content-Type": "image/jpeg" },
      });
    });

    await expect(
      generateBlurHash("https://cdn.example.com/not-a-jpeg", {
        fetch: fetchMock,
      }),
    ).resolves.toEqual({
      blurhash: null,
      warnings: ["blurhash_decode_failed"],
    });
  });
});

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
