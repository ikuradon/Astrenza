import { encode as encodeBlurHash } from "blurhash";
import { decode as decodeJpeg } from "jpeg-js";
import { validateFetchUrl, validateRedirectLocation } from "./url-guard";

export const BLURHASH_TRANSFORM_WIDTH = 32;
export const BLURHASH_TRANSFORM_HEIGHT = 32;
export const BLURHASH_MAX_JPEG_BYTES = 256 * 1024;
export const DEFAULT_BLURHASH_TIMEOUT_MS = 8000;
export const DEFAULT_BLURHASH_MAX_REDIRECTS = 5;

export type BlurHashWarning = "blurhash_failed" | "blurhash_decode_failed";

export type GenerateBlurHashResult = {
  blurhash: string | null;
  warnings: BlurHashWarning[];
};

export type GenerateBlurHashOptions = {
  fetch?: typeof fetch;
  fetchBlurHashSource?: (
    url: string,
    signal: AbortSignal,
  ) => Promise<Response>;
  maxBytes?: number;
  maxRedirects?: number;
  timeoutMs?: number;
  signal?: AbortSignal;
  serviceOrigin?: string;
};

type CloudflareImageFit = "scale-down";
type CloudflareImageFormat = "jpeg";

type CloudflareImageOptions = {
  width: number;
  height: number;
  fit: CloudflareImageFit;
  format: CloudflareImageFormat;
  quality: number;
};

type CloudflareImageRequestInit = RequestInit & {
  cf?: {
    image?: CloudflareImageOptions;
  };
};

export async function generateBlurHash(
  url: string,
  options: GenerateBlurHashOptions = {},
): Promise<GenerateBlurHashResult> {
  const guard = validateFetchUrl(url, {
    serviceOrigin: options.serviceOrigin,
  });
  if (!guard.ok) {
    return failedResult("blurhash_failed");
  }

  const fetchImpl = options.fetch ?? fetch;
  const signal = combinedSignal(
    options.signal,
    options.timeoutMs ?? DEFAULT_BLURHASH_TIMEOUT_MS,
  );
  const maxBytes = positiveLimit(options.maxBytes, BLURHASH_MAX_JPEG_BYTES);

  let response: Response;
  try {
    response = options.fetchBlurHashSource
      ? await options.fetchBlurHashSource(guard.url, signal)
      : await fetchBlurHashImage(fetchImpl, guard.url, {
          maxRedirects: options.maxRedirects ?? DEFAULT_BLURHASH_MAX_REDIRECTS,
          serviceOrigin: options.serviceOrigin,
          signal,
        });
  } catch {
    return failedResult("blurhash_failed");
  }

  if (!isSuccessStatus(response.status)) {
    await cancelResponseBody(response);
    return failedResult("blurhash_failed");
  }

  let jpegBytes: Uint8Array;
  try {
    const read = await readLimitedBytes(response, maxBytes);
    if (read.truncated) {
      return failedResult("blurhash_failed");
    }
    jpegBytes = read.bytes;
  } catch {
    return failedResult("blurhash_failed");
  }

  try {
    const decoded = decodeJpeg(jpegBytes, {
      useTArray: true,
      formatAsRGBA: true,
      tolerantDecoding: true,
    });
    const pixels = new Uint8ClampedArray(
      decoded.data.buffer,
      decoded.data.byteOffset,
      decoded.data.byteLength,
    );

    return {
      blurhash: encodeBlurHash(pixels, decoded.width, decoded.height, 4, 3),
      warnings: [],
    };
  } catch {
    return failedResult("blurhash_decode_failed");
  }
}

type FetchBlurHashImageOptions = {
  maxRedirects: number;
  serviceOrigin?: string;
  signal: AbortSignal;
};

async function fetchBlurHashImage(
  fetchImpl: typeof fetch,
  url: string,
  options: FetchBlurHashImageOptions,
): Promise<Response> {
  let currentUrl = url;

  for (
    let redirectCount = 0;
    redirectCount <= options.maxRedirects;
    redirectCount += 1
  ) {
    const response = await fetchImpl(currentUrl, blurHashRequestInit(options.signal));
    if (!isRedirectStatus(response.status)) {
      return response;
    }

    if (redirectCount === options.maxRedirects) {
      await cancelResponseBody(response);
      throw new Error("too_many_redirects");
    }

    const location = response.headers.get("Location");
    if (!location) {
      await cancelResponseBody(response);
      throw new Error("missing_redirect_location");
    }

    const guard = validateRedirectLocation(location, new URL(currentUrl), {
      serviceOrigin: options.serviceOrigin,
    });
    if (!guard.ok) {
      await cancelResponseBody(response);
      throw new Error("unsafe_redirect");
    }

    await cancelResponseBody(response);
    currentUrl = guard.url;
  }

  throw new Error("too_many_redirects");
}

function blurHashRequestInit(signal: AbortSignal): CloudflareImageRequestInit {
  return {
    headers: {
      Accept: "image/jpeg",
      "User-Agent": "AstrenzaMediaResolver/1.0",
    },
    redirect: "manual",
    signal,
    cf: {
      image: {
        width: BLURHASH_TRANSFORM_WIDTH,
        height: BLURHASH_TRANSFORM_HEIGHT,
        fit: "scale-down",
        format: "jpeg",
        quality: 60,
      },
    },
  };
}

async function readLimitedBytes(
  response: Response,
  maxBytes: number,
): Promise<{ bytes: Uint8Array; truncated: boolean }> {
  if (!response.body) {
    return { bytes: new Uint8Array(), truncated: false };
  }

  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let bytesRead = 0;

  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      if (!value) continue;

      const remaining = maxBytes - bytesRead;
      if (remaining <= 0) {
        await reader.cancel();
        return { bytes: concatChunks(chunks, bytesRead), truncated: true };
      }

      if (value.byteLength > remaining) {
        chunks.push(value.slice(0, remaining));
        bytesRead += remaining;
        await reader.cancel();
        return { bytes: concatChunks(chunks, bytesRead), truncated: true };
      }

      chunks.push(value);
      bytesRead += value.byteLength;
      if (bytesRead >= maxBytes) {
        await reader.cancel();
        return { bytes: concatChunks(chunks, bytesRead), truncated: true };
      }
    }
  } finally {
    reader.releaseLock();
  }

  return { bytes: concatChunks(chunks, bytesRead), truncated: false };
}

function concatChunks(chunks: Uint8Array[], totalLength: number): Uint8Array {
  const result = new Uint8Array(totalLength);
  let offset = 0;
  for (const chunk of chunks) {
    result.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return result;
}

function failedResult(warning: BlurHashWarning): GenerateBlurHashResult {
  return {
    blurhash: null,
    warnings: [warning],
  };
}

async function cancelResponseBody(response: Response): Promise<void> {
  try {
    await response.body?.cancel();
  } catch {
    // runtime 側で cancel できない場合も、返す結果は揺らさない。
  }
}

function combinedSignal(
  callerSignal: AbortSignal | undefined,
  timeoutMs: number,
): AbortSignal {
  const timeoutSignal = AbortSignal.timeout(timeoutMs);
  if (!callerSignal) return timeoutSignal;

  if (typeof AbortSignal.any === "function") {
    return AbortSignal.any([callerSignal, timeoutSignal]);
  }

  const controller = new AbortController();
  const abort = () => {
    if (!controller.signal.aborted) {
      controller.abort(callerSignal.reason ?? timeoutSignal.reason);
    }
  };

  callerSignal.addEventListener("abort", abort, { once: true });
  timeoutSignal.addEventListener("abort", abort, { once: true });
  if (callerSignal.aborted || timeoutSignal.aborted) {
    abort();
  }

  return controller.signal;
}

function isSuccessStatus(status: number): boolean {
  return status >= 200 && status < 300;
}

function isRedirectStatus(status: number): boolean {
  return status >= 300 && status < 400;
}

function positiveLimit(value: number | undefined, fallback: number): number {
  if (!Number.isFinite(value) || value === undefined || value <= 0) {
    return fallback;
  }

  return Math.min(Math.floor(value), fallback);
}
