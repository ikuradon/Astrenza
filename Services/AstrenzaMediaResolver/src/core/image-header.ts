import { validateFetchUrl, validateRedirectLocation } from "./url-guard";

export const MAX_IMAGE_PROBE_BYTES = 128 * 1024;
export const DEFAULT_IMAGE_PROBE_TIMEOUT_MS = 8000;
export const DEFAULT_IMAGE_PROBE_MAX_REDIRECTS = 5;

export type ImageMimeType = "image/png" | "image/jpeg" | "image/webp";

export type ParsedImageHeader = {
  width: number | null;
  height: number | null;
  mimeType: ImageMimeType | null;
};

export type ImageProbeWarning = "image_probe_truncated";

export type ImageProbeResult = ParsedImageHeader & {
  warnings: ImageProbeWarning[];
};

export type ProbeImageHeaderOptions = {
  fetch?: typeof fetch;
  maxBytes?: number;
  timeoutMs?: number;
  maxRedirects?: number;
  signal?: AbortSignal;
  serviceOrigin?: string;
};

export type ImageProbeErrorCode =
  | "unsafe_url"
  | "http_status"
  | "missing_redirect_location"
  | "unsafe_redirect"
  | "too_many_redirects";

export class ImageProbeError extends Error {
  readonly code: ImageProbeErrorCode;
  readonly status?: number;
  readonly guardError?: string;

  constructor(
    code: ImageProbeErrorCode,
    options: { status?: number; guardError?: string } = {},
  ) {
    super(code);
    this.name = "ImageProbeError";
    this.code = code;
    this.status = options.status;
    this.guardError = options.guardError;
  }
}

export function parseImageHeader(
  input: ArrayBuffer | ArrayBufferView,
): ParsedImageHeader {
  const bytes = toBytes(input);

  return (
    parsePngHeader(bytes) ??
    parseJpegHeader(bytes) ??
    parseWebpHeader(bytes) ??
    emptyHeader()
  );
}

export async function probeImageHeader(
  url: string,
  options: ProbeImageHeaderOptions = {},
): Promise<ImageProbeResult> {
  const fetchImpl = options.fetch ?? fetch;
  const maxBytes = positiveLimit(options.maxBytes, MAX_IMAGE_PROBE_BYTES);
  const maxRedirects =
    options.maxRedirects ?? DEFAULT_IMAGE_PROBE_MAX_REDIRECTS;
  const signal = combinedSignal(
    options.signal,
    options.timeoutMs ?? DEFAULT_IMAGE_PROBE_TIMEOUT_MS,
  );

  const initialGuard = validateFetchUrl(url, {
    serviceOrigin: options.serviceOrigin,
  });
  if (!initialGuard.ok) {
    throw new ImageProbeError("unsafe_url", {
      guardError: initialGuard.error,
    });
  }

  let probeUrl = initialGuard.url;
  const head = await fetchImageProbeRequest(fetchImpl, probeUrl, {
    method: "HEAD",
    maxRedirects,
    serviceOrigin: options.serviceOrigin,
    signal,
  });
  probeUrl = head.finalUrl;

  const headIsUnavailable =
    head.response.status === 405 || head.response.status === 501;

  if (isSuccessStatus(head.response.status)) {
    await cancelResponseBody(head.response);
  } else {
    await cancelResponseBody(head.response);
  }

  if (!headIsUnavailable && !isSuccessStatus(head.response.status)) {
    probeUrl = initialGuard.url;
  }

  const get = await fetchImageProbeRequest(fetchImpl, probeUrl, {
    method: "GET",
    maxRedirects,
    serviceOrigin: options.serviceOrigin,
    signal,
    rangeEnd: maxBytes - 1,
  });

  if (!isSuccessStatus(get.response.status)) {
    await cancelResponseBody(get.response);
    throw new ImageProbeError("http_status", { status: get.response.status });
  }

  const { bytes, warnings } = await readLimitedBytes(get.response, maxBytes);
  return {
    ...parseImageHeader(bytes),
    warnings,
  };
}

function parsePngHeader(bytes: Uint8Array): ParsedImageHeader | null {
  if (bytes.byteLength < 24) return null;
  if (
    bytes[0] !== 0x89 ||
    bytes[1] !== 0x50 ||
    bytes[2] !== 0x4e ||
    bytes[3] !== 0x47 ||
    bytes[4] !== 0x0d ||
    bytes[5] !== 0x0a ||
    bytes[6] !== 0x1a ||
    bytes[7] !== 0x0a
  ) {
    return null;
  }

  if (dataView(bytes).getUint32(8, false) !== 13) return null;
  if (!asciiEquals(bytes, 12, "IHDR")) return null;

  const view = dataView(bytes);
  return dimensions(
    view.getUint32(16, false),
    view.getUint32(20, false),
    "image/png",
  );
}

function parseJpegHeader(bytes: Uint8Array): ParsedImageHeader | null {
  if (bytes.byteLength < 4) return null;
  if (bytes[0] !== 0xff || bytes[1] !== 0xd8) return null;

  const view = dataView(bytes);
  let offset = 2;

  while (offset < bytes.byteLength) {
    if (bytes[offset] !== 0xff) return null;

    while (offset < bytes.byteLength && bytes[offset] === 0xff) {
      offset += 1;
    }
    if (offset >= bytes.byteLength) return null;

    const marker = bytes[offset];
    offset += 1;

    if (marker === 0xda || marker === 0xd9) return null;
    if (isStandaloneJpegMarker(marker)) continue;

    if (offset + 2 > bytes.byteLength) return null;
    const segmentLength = view.getUint16(offset, false);
    if (segmentLength < 2) return null;

    const segmentEnd = offset + segmentLength;
    if (segmentEnd > bytes.byteLength) return null;

    if (marker === 0xc0 || marker === 0xc2) {
      const heightOffset = offset + 3;
      const widthOffset = offset + 5;
      if (widthOffset + 2 > segmentEnd) return null;

      return dimensions(
        view.getUint16(widthOffset, false),
        view.getUint16(heightOffset, false),
        "image/jpeg",
      );
    }

    offset = segmentEnd;
  }

  return null;
}

function parseWebpHeader(bytes: Uint8Array): ParsedImageHeader | null {
  if (bytes.byteLength < 20) return null;
  if (!asciiEquals(bytes, 0, "RIFF") || !asciiEquals(bytes, 8, "WEBP")) {
    return null;
  }

  if (asciiEquals(bytes, 12, "VP8X")) {
    if (bytes.byteLength < 30) return null;
    if (dataView(bytes).getUint32(16, true) !== 10) return null;
    return dimensions(
      readUint24Le(bytes, 24) + 1,
      readUint24Le(bytes, 27) + 1,
      "image/webp",
    );
  }

  if (asciiEquals(bytes, 12, "VP8L")) {
    if (bytes.byteLength < 25 || bytes[20] !== 0x2f) return null;
    if (dataView(bytes).getUint32(16, true) < 5) return null;

    const bits = dataView(bytes).getUint32(21, true);
    return dimensions(
      (bits & 0x3fff) + 1,
      ((bits >>> 14) & 0x3fff) + 1,
      "image/webp",
    );
  }

  return null;
}

type FetchProbeRequestOptions = {
  method: "HEAD" | "GET";
  maxRedirects: number;
  serviceOrigin?: string;
  signal: AbortSignal;
  rangeEnd?: number;
};

type FetchProbeResponse = {
  response: Response;
  finalUrl: string;
};

async function fetchImageProbeRequest(
  fetchImpl: typeof fetch,
  url: string,
  options: FetchProbeRequestOptions,
): Promise<FetchProbeResponse> {
  let currentUrl = url;

  for (
    let redirectCount = 0;
    redirectCount <= options.maxRedirects;
    redirectCount += 1
  ) {
    const response = await fetchImpl(currentUrl, {
      method: options.method,
      headers: imageProbeHeaders(options.rangeEnd),
      redirect: "manual",
      signal: options.signal,
    });

    if (!isRedirectStatus(response.status)) {
      return { response, finalUrl: currentUrl };
    }

    if (redirectCount === options.maxRedirects) {
      await cancelResponseBody(response);
      throw new ImageProbeError("too_many_redirects", {
        status: response.status,
      });
    }

    const location = response.headers.get("Location");
    if (!location) {
      await cancelResponseBody(response);
      throw new ImageProbeError("missing_redirect_location", {
        status: response.status,
      });
    }

    const guard = validateRedirectLocation(location, new URL(currentUrl), {
      serviceOrigin: options.serviceOrigin,
    });
    if (!guard.ok) {
      await cancelResponseBody(response);
      throw new ImageProbeError("unsafe_redirect", {
        status: response.status,
        guardError: guard.error,
      });
    }

    await cancelResponseBody(response);
    currentUrl = guard.url;
  }

  throw new ImageProbeError("too_many_redirects");
}

function imageProbeHeaders(rangeEnd: number | undefined): Record<string, string> {
  const headers: Record<string, string> = {
    Accept: "image/png,image/jpeg,image/webp,*/*;q=0.8",
    "User-Agent": "AstrenzaMediaResolver/1.0",
  };

  if (rangeEnd !== undefined) {
    headers.Range = `bytes=0-${rangeEnd}`;
  }

  return headers;
}

async function readLimitedBytes(
  response: Response,
  maxBytes: number,
): Promise<{ bytes: Uint8Array; warnings: ImageProbeWarning[] }> {
  if (!response.body) {
    return { bytes: new Uint8Array(), warnings: [] };
  }

  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let bytesRead = 0;
  let truncated = false;

  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      if (!value) continue;

      const remaining = maxBytes - bytesRead;
      if (remaining <= 0) {
        truncated = true;
        await reader.cancel();
        break;
      }

      if (value.byteLength > remaining) {
        chunks.push(value.slice(0, remaining));
        bytesRead += remaining;
        truncated = true;
        await reader.cancel();
        break;
      }

      chunks.push(value);
      bytesRead += value.byteLength;
      if (bytesRead >= maxBytes) {
        truncated = true;
        await reader.cancel();
        break;
      }
    }
  } finally {
    reader.releaseLock();
  }

  return {
    bytes: concatChunks(chunks, bytesRead),
    warnings: truncated ? ["image_probe_truncated"] : [],
  };
}

async function cancelResponseBody(response: Response): Promise<void> {
  try {
    await response.body?.cancel();
  } catch {
    // runtime 側で cancel できない場合も、返す結果は揺らさない。
  }
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

function isStandaloneJpegMarker(marker: number | undefined): boolean {
  return (
    marker === 0x01 ||
    marker === 0xd8 ||
    (marker !== undefined && marker >= 0xd0 && marker <= 0xd7)
  );
}

function positiveLimit(value: number | undefined, fallback: number): number {
  if (!Number.isFinite(value) || value === undefined || value <= 0) {
    return fallback;
  }

  return Math.min(Math.floor(value), fallback);
}

function dimensions(
  width: number,
  height: number,
  mimeType: ImageMimeType,
): ParsedImageHeader {
  if (!Number.isSafeInteger(width) || !Number.isSafeInteger(height)) {
    return emptyHeader();
  }

  if (width <= 0 || height <= 0) {
    return emptyHeader();
  }

  return { width, height, mimeType };
}

function emptyHeader(): ParsedImageHeader {
  return { width: null, height: null, mimeType: null };
}

function toBytes(input: ArrayBuffer | ArrayBufferView): Uint8Array {
  if (input instanceof ArrayBuffer) {
    return new Uint8Array(input);
  }

  return new Uint8Array(input.buffer, input.byteOffset, input.byteLength);
}

function dataView(bytes: Uint8Array): DataView {
  return new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
}

function readUint24Le(bytes: Uint8Array, offset: number): number {
  return (
    (bytes[offset] ?? 0) |
    ((bytes[offset + 1] ?? 0) << 8) |
    ((bytes[offset + 2] ?? 0) << 16)
  );
}

function asciiEquals(
  bytes: Uint8Array,
  offset: number,
  expected: string,
): boolean {
  if (offset + expected.length > bytes.byteLength) return false;

  for (let index = 0; index < expected.length; index += 1) {
    if (bytes[offset + index] !== expected.charCodeAt(index)) {
      return false;
    }
  }

  return true;
}
