import { describe, expect, it, vi } from "vitest";
import {
  MAX_IMAGE_PROBE_BYTES,
  parseImageHeader,
  probeImageHeader,
} from "../src/core/image-header";

const tinyPngBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAIAAAADCAYAAAAAAAAA";
const tinyJpegBase64 = "/9j/4QAMRXhpZgAAdGluef/AABEIAAcABQMBEQACEQADEQD/2Q==";
const tinyWebpBase64 = "UklGRhYAAABXRUJQVlA4WAoAAAAAAAAACgAADAAA";
const emptyHeader = { width: null, height: null, mimeType: null };

describe("parseImageHeader", () => {
  it("reads PNG IHDR dimensions", () => {
    expect(parseImageHeader(fixtureBytes(tinyPngBase64))).toEqual({
      width: 2,
      height: 3,
      mimeType: "image/png",
    });
  });

  it("scans JPEG SOF0 after APP/EXIF segments", () => {
    expect(parseImageHeader(fixtureBytes(tinyJpegBase64))).toEqual({
      width: 5,
      height: 7,
      mimeType: "image/jpeg",
    });
  });

  it("scans JPEG SOF2 dimensions", () => {
    expect(parseImageHeader(jpegWithSof(0xc2, 144, 88))).toEqual({
      width: 144,
      height: 88,
      mimeType: "image/jpeg",
    });
  });

  it("reads WebP VP8X dimensions", () => {
    expect(parseImageHeader(fixtureBytes(tinyWebpBase64))).toEqual({
      width: 11,
      height: 13,
      mimeType: "image/webp",
    });
  });

  it("reads WebP VP8L dimensions", () => {
    expect(parseImageHeader(webpVp8l(31, 17))).toEqual({
      width: 31,
      height: 17,
      mimeType: "image/webp",
    });
  });

  it.each([
    new Uint8Array(),
    bytes(0x47, 0x49, 0x46, 0x38),
    pngWithIhdrLength(12),
    fixtureBytes(tinyPngBase64).slice(0, 20),
    jpegWithSof(0xc0, 24, 16).slice(0, 14),
    webpVp8xWithChunkSize(9),
    webpVp8lWithChunkSize(4, 31, 17),
    fixtureBytes(tinyWebpBase64).slice(0, 24),
  ])("returns null dimensions for unsupported or truncated input", (buffer) => {
    expect(parseImageHeader(buffer)).toEqual(emptyHeader);
  });
});

describe("probeImageHeader", () => {
  it("uses HEAD before bounded ranged GET", async () => {
    const png = fixtureBytes(tinyPngBase64);
    const calls: Array<{ input: RequestInfo | URL; init?: RequestInit }> = [];
    const fetchMock = vi.fn<typeof fetch>(async (input, init) => {
      calls.push({ input, init });
      if (init?.method === "HEAD") {
        return new Response(null, {
          status: 200,
          headers: {
            "Content-Type": "image/png",
            "Content-Length": String(png.byteLength),
          },
        });
      }

      return new Response(bodyBytes(png), {
        status: 206,
        headers: { "Content-Type": "image/png" },
      });
    });

    const result = await probeImageHeader("https://example.com/tiny.png", {
      fetch: fetchMock,
    });

    expect(result).toEqual({
      width: 2,
      height: 3,
      mimeType: "image/png",
      warnings: [],
    });
    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(calls[0]?.init?.method).toBe("HEAD");
    expect(calls[1]?.init?.method).toBe("GET");
    expect(calls[1]?.init?.headers).toMatchObject({
      Range: `bytes=0-${MAX_IMAGE_PROBE_BYTES - 1}`,
    });
  });

  it("falls back to ranged GET when HEAD is not available", async () => {
    const png = fixtureBytes(tinyPngBase64);
    const fetchMock = vi.fn<typeof fetch>(async (_input, init) => {
      if (init?.method === "HEAD") {
        return new Response(null, { status: 405 });
      }

      return new Response(bodyBytes(png), {
        status: 206,
        headers: { "Content-Type": "image/png" },
      });
    });

    const result = await probeImageHeader("https://example.com/tiny.png", {
      fetch: fetchMock,
    });

    expect(result.width).toBe(2);
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it("treats HEAD content metadata as hints and still parses bounded GET bytes", async () => {
    const png = fixtureBytes(tinyPngBase64);
    const fetchMock = vi.fn<typeof fetch>(async (_input, init) => {
      if (init?.method === "HEAD") {
        return new Response(null, {
          status: 200,
          headers: {
            "Content-Type": "application/octet-stream",
            "Content-Length": "0",
          },
        });
      }

      return new Response(bodyBytes(png), {
        status: 206,
        headers: { "Content-Type": "application/octet-stream" },
      });
    });

    const result = await probeImageHeader("https://example.com/tiny.png", {
      fetch: fetchMock,
    });

    expect(result).toEqual({
      width: 2,
      height: 3,
      mimeType: "image/png",
      warnings: [],
    });
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it("cancels ignored Range responses that exceed the probe limit", async () => {
    const png = fixtureBytes(tinyPngBase64);
    let cancelled = false;
    let pullCount = 0;
    const body = new ReadableStream<Uint8Array>({
      pull(controller) {
        if (pullCount === 0) {
          controller.enqueue(png);
        } else if (pullCount === 1) {
          controller.enqueue(bytes(0, 1, 2, 3, 4, 5, 6, 7));
        }
        pullCount += 1;
      },
      cancel() {
        cancelled = true;
      },
    });
    const fetchMock = vi.fn<typeof fetch>(async (_input, init) => {
      if (init?.method === "HEAD") {
        return new Response(null, { status: 501 });
      }

      return new Response(body, {
        status: 200,
        headers: { "Content-Type": "image/png" },
      });
    });

    const result = await probeImageHeader("https://example.com/tiny.png", {
      fetch: fetchMock,
      maxBytes: png.byteLength,
    });

    expect(result).toEqual({
      width: 2,
      height: 3,
      mimeType: "image/png",
      warnings: ["image_probe_truncated"],
    });
    expect(cancelled).toBe(true);
  });

  it("cancels ignored Range responses as soon as the exact byte limit is reached", async () => {
    const png = fixtureBytes(tinyPngBase64);
    let cancelled = false;
    const body = new ReadableStream<Uint8Array>({
      pull(controller) {
        controller.enqueue(png);
      },
      cancel() {
        cancelled = true;
      },
    });
    const fetchMock = vi.fn<typeof fetch>(async (_input, init) => {
      if (init?.method === "HEAD") {
        return new Response(null, { status: 501 });
      }

      return new Response(body, {
        status: 200,
        headers: { "Content-Type": "image/png" },
      });
    });

    const result = await probeImageHeader("https://example.com/tiny.png", {
      fetch: fetchMock,
      maxBytes: png.byteLength,
    });

    expect(result.warnings).toEqual(["image_probe_truncated"]);
    expect(cancelled).toBe(true);
  });
});

function fixtureBytes(base64: string): Uint8Array {
  return decodeBase64(base64.trim());
}

function jpegWithSof(marker: number, width: number, height: number): Uint8Array {
  const app = ascii("Exif\0\0ignored");
  return bytes(
    0xff,
    0xd8,
    0xff,
    0xe1,
    ...be16(app.byteLength + 2),
    ...app,
    0xff,
    marker,
    ...be16(17),
    8,
    ...be16(height),
    ...be16(width),
    3,
    1,
    0x11,
    0,
    2,
    0x11,
    0,
    3,
    0x11,
    0,
    0xff,
    0xd9,
  );
}

function webpVp8l(width: number, height: number): Uint8Array {
  const packed = (width - 1) | ((height - 1) << 14);
  return bytes(
    ...ascii("RIFF"),
    ...le32(17),
    ...ascii("WEBP"),
    ...ascii("VP8L"),
    ...le32(5),
    0x2f,
    packed & 0xff,
    (packed >>> 8) & 0xff,
    (packed >>> 16) & 0xff,
    (packed >>> 24) & 0xff,
  );
}

function pngWithIhdrLength(length: number): Uint8Array {
  const png = fixtureBytes(tinyPngBase64);
  const copy = new Uint8Array(png);
  copy[8] = (length >>> 24) & 0xff;
  copy[9] = (length >>> 16) & 0xff;
  copy[10] = (length >>> 8) & 0xff;
  copy[11] = length & 0xff;
  return copy;
}

function webpVp8xWithChunkSize(chunkSize: number): Uint8Array {
  return bytes(
    ...ascii("RIFF"),
    ...le32(22),
    ...ascii("WEBP"),
    ...ascii("VP8X"),
    ...le32(chunkSize),
    0,
    0,
    0,
    0,
    10,
    0,
    0,
    12,
    0,
    0,
  );
}

function webpVp8lWithChunkSize(
  chunkSize: number,
  width: number,
  height: number,
): Uint8Array {
  const webp = webpVp8l(width, height);
  const copy = new Uint8Array(webp);
  copy.set(le32(chunkSize), 16);
  return copy;
}

function decodeBase64(value: string): Uint8Array {
  const decoded = atob(value);
  return Uint8Array.from(decoded, (char) => char.charCodeAt(0));
}

function ascii(value: string): Uint8Array {
  return new TextEncoder().encode(value);
}

function bytes(...values: number[]): Uint8Array {
  return Uint8Array.from(values);
}

function bodyBytes(value: Uint8Array): ArrayBuffer {
  const copy = new Uint8Array(value.byteLength);
  copy.set(value);
  return copy.buffer;
}

function be16(value: number): number[] {
  return [(value >>> 8) & 0xff, value & 0xff];
}

function le32(value: number): number[] {
  return [
    value & 0xff,
    (value >>> 8) & 0xff,
    (value >>> 16) & 0xff,
    (value >>> 24) & 0xff,
  ];
}
