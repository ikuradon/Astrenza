import type { ResolveImagePreset } from "../core/schema";
import { validateFetchUrl, validateRedirectLocation } from "../core/url-guard";
import type { ImageTransformer } from "./adapter";

type CloudflareImageFit = "scale-down";
type CloudflareImageFormat = "avif" | "webp" | "jpeg";

type ImagePreset = {
  width: number;
  height?: number;
  quality: number;
  fit: CloudflareImageFit;
  format?: CloudflareImageFormat;
};

type CloudflareImageOptions = ImagePreset & {
  format: CloudflareImageFormat;
};

type CloudflareImageRequestInit = RequestInit & {
  cf?: {
    image?: CloudflareImageOptions;
  };
};

export const imagePresets = {
  timeline: { width: 900, quality: 72, fit: "scale-down" },
  thumb: { width: 360, quality: 68, fit: "scale-down" },
  "blurhash-source": {
    width: 32,
    height: 32,
    quality: 60,
    fit: "scale-down",
    format: "jpeg",
  },
} as const satisfies Record<ResolveImagePreset, ImagePreset>;

export type ImagePresetName = keyof typeof imagePresets;

export const IMAGE_CACHE_CONTROL =
  "public, max-age=86400, stale-while-revalidate=7200, stale-if-error=3600, s-maxage=1209600";
export const IMAGE_ERROR_CACHE_CONTROL = "no-store";

const MAX_IMAGE_REDIRECTS = 5;
const SAFE_UPSTREAM_HEADERS = [
  "Accept",
  "Accept-Language",
  "If-None-Match",
  "If-Modified-Since",
] as const;
const SAFE_RESPONSE_HEADERS = [
  "Content-Type",
  "Content-Length",
  "ETag",
  "Last-Modified",
] as const;

export type CloudflareImageResult =
  | {
      ok: true;
      response: Response;
    }
  | {
      ok: false;
      error: string;
      status: number;
    };

export type FetchCloudflareImageOptions = {
  fetch?: typeof fetch;
  serviceOrigin: string;
  maxRedirects?: number;
  imageRequestInit?: ImageRequestInitFactory;
};

type ImageRequestInitFactory = (
  request: Request,
  preset: ImagePresetName,
) => RequestInit;

export function isImagePresetName(value: string): value is ImagePresetName {
  return Object.hasOwn(imagePresets, value);
}

export function optimizedImageUrl(
  serviceOrigin: string,
  preset: ImagePresetName,
  imageUrl: string,
): string {
  const url = new URL(`/v1/image/${preset}`, serviceOrigin);
  url.searchParams.set("url", imageUrl);
  return url.href;
}

export async function fetchCloudflareImage(
  request: Request,
  targetUrl: string,
  preset: ImagePresetName,
  options: FetchCloudflareImageOptions,
): Promise<CloudflareImageResult> {
  const guard = validateFetchUrl(targetUrl, {
    serviceOrigin: options.serviceOrigin,
  });
  if (!guard.ok) {
    return { ok: false, error: guard.error, status: 400 };
  }

  const fetchImpl = options.fetch ?? fetch;
  const maxRedirects = options.maxRedirects ?? MAX_IMAGE_REDIRECTS;
  const requestInit = options.imageRequestInit ?? cloudflareImageRequestInit;
  let currentUrl = guard.url;

  for (
    let redirectCount = 0;
    redirectCount <= maxRedirects;
    redirectCount += 1
  ) {
    let response: Response;
    try {
      response = await fetchImpl(currentUrl, requestInit(request, preset));
    } catch {
      return { ok: false, error: "upstream_fetch_failed", status: 502 };
    }
    if (!isRedirectStatus(response.status)) {
      if (isUnexpectedSuccessContentType(response)) {
        await cancelResponseBody(response);
        return { ok: false, error: "upstream_non_image", status: 502 };
      }

      return {
        ok: true,
        response: transformedImageResponse(response),
      };
    }

    if (redirectCount === maxRedirects) {
      await cancelResponseBody(response);
      return { ok: false, error: "too_many_redirects", status: 400 };
    }

    const location = response.headers.get("Location");
    if (!location) {
      await cancelResponseBody(response);
      return { ok: false, error: "missing_redirect_location", status: 400 };
    }

    const redirectGuard = validateRedirectLocation(
      location,
      new URL(currentUrl),
      { serviceOrigin: options.serviceOrigin },
    );
    if (!redirectGuard.ok) {
      await cancelResponseBody(response);
      return { ok: false, error: "unsafe_redirect", status: 400 };
    }

    await cancelResponseBody(response);
    currentUrl = redirectGuard.url;
  }

  return { ok: false, error: "too_many_redirects", status: 400 };
}

export function createPassThroughImageTransformer(
  fetchImpl?: typeof fetch,
): ImageTransformer {
  return (request, targetUrl, preset, options) =>
    fetchCloudflareImage(request, targetUrl, preset, {
      fetch: fetchImpl ?? options.fetch,
      serviceOrigin: options.serviceOrigin,
      imageRequestInit: passThroughImageRequestInit,
    });
}

function cloudflareImageRequestInit(
  request: Request,
  preset: ImagePresetName,
): CloudflareImageRequestInit {
  return {
    headers: safeUpstreamHeaders(request),
    redirect: "manual",
    signal: request.signal,
    cf: {
      image: {
        ...imagePresets[preset],
        format: negotiatedFormat(request, preset),
      },
    },
  };
}

function passThroughImageRequestInit(request: Request): RequestInit {
  return {
    headers: safeUpstreamHeaders(request),
    redirect: "manual",
    signal: request.signal,
  };
}

function safeUpstreamHeaders(request: Request): Headers {
  const headers = new Headers();
  for (const name of SAFE_UPSTREAM_HEADERS) {
    const value = request.headers.get(name);
    if (value) {
      headers.set(name, value);
    }
  }
  return headers;
}

function negotiatedFormat(
  request: Request,
  preset: ImagePresetName,
): CloudflareImageFormat {
  const presetConfig: ImagePreset = imagePresets[preset];
  const fixedFormat = presetConfig.format;
  if (fixedFormat) return fixedFormat;

  const accept = request.headers.get("Accept") ?? "";
  if (acceptsMediaType(accept, "image/avif")) return "avif";
  if (acceptsMediaType(accept, "image/webp")) return "webp";
  return "jpeg";
}

function acceptsMediaType(accept: string, mediaType: string): boolean {
  return accept.split(",").some((entry) => {
    const [type, ...parameters] = entry.split(";").map((part) => part.trim());
    if (type?.toLowerCase() !== mediaType) return false;

    const q = parameters.find((parameter) =>
      parameter.toLowerCase().startsWith("q="),
    );
    if (!q) return true;

    const quality = Number.parseFloat(q.slice(2));
    return Number.isNaN(quality) || quality > 0;
  });
}

function transformedImageResponse(response: Response): Response {
  const headers = new Headers();
  for (const name of SAFE_RESPONSE_HEADERS) {
    const value = response.headers.get(name);
    if (value) {
      headers.set(name, value);
    }
  }
  headers.set(
    "Cache-Control",
    isSuccessStatus(response.status) ? IMAGE_CACHE_CONTROL : IMAGE_ERROR_CACHE_CONTROL,
  );
  headers.set("Vary", "Accept");

  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}

async function cancelResponseBody(response: Response): Promise<void> {
  try {
    await response.body?.cancel();
  } catch {
    // runtime 側で cancel できない場合も、返す結果は揺らさない。
  }
}

function isRedirectStatus(status: number): boolean {
  return status >= 300 && status < 400;
}

function isSuccessStatus(status: number): boolean {
  return status >= 200 && status < 300;
}

function isUnexpectedSuccessContentType(response: Response): boolean {
  if (!isSuccessStatus(response.status)) return false;

  const contentType = response.headers.get("Content-Type");
  if (!contentType) return true;
  return !contentType.toLowerCase().startsWith("image/");
}
