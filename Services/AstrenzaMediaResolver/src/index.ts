import { bearerToken, verifyBearerToken } from "./core/auth";
import { generateBlurHash, type GenerateBlurHashOptions } from "./core/blurhash";
import {
  DEFAULT_IMAGE_PROBE_TIMEOUT_MS,
  ImageProbeError,
  probeImageHeader,
} from "./core/image-header";
import {
  FetchHtmlError,
  fetchHtmlDocument,
  parseHtmlMetadata,
} from "./core/html-metadata";
import type {
  ResolveBatchRequest,
  ResolveItem,
  ResolveResult,
  ResolvedImage,
} from "./core/schema";
import { validateFetchUrl } from "./core/url-guard";
import {
  FAILED_CACHE_TTL_SECONDS,
  readResolveCache,
  writeResolveCache,
  type MetaCacheBinding,
} from "./runtime/cloudflare-cache";
import {
  createCloudflareRuntimeAdapter,
  type RuntimeAdapter,
  type RuntimeAdapterFactory,
} from "./runtime/adapter";
import {
  fetchCloudflareImage,
  isImagePresetName,
  optimizedImageUrl,
  type ImagePresetName,
} from "./runtime/cloudflare-image";

type ResolverEnv = Env & {
  ASTRENZA_SERVICE_TOKEN?: string;
  META_CACHE?: MetaCacheBinding;
};

type MediaResolverHandler<AdapterEnv, AdapterContext> = {
  fetch(
    request: Request,
    env: AdapterEnv,
    ctx: AdapterContext,
  ): Promise<Response>;
};

type CreateMediaResolverHandlerOptions<AdapterEnv, AdapterContext> = {
  runtimeAdapter?: RuntimeAdapterFactory<AdapterEnv, AdapterContext>;
};

type ResolveContext = {
  fetch: typeof fetch;
  cache: MetaCacheBinding | undefined;
  cacheTtlSeconds: number;
  imageTransformer: RuntimeAdapter["imageTransformer"];
  imagePreset: ImagePresetName;
  maxHtmlBytes: number;
  maxImageProbeBytes: number;
  schedule: (task: Promise<unknown>) => void;
  serviceOrigin: string;
};

type ImageResolution = {
  image: ResolvedImage;
  warnings: string[];
};

export function createMediaResolverHandler(): MediaResolverHandler<
  ResolverEnv,
  ExecutionContext
>;
export function createMediaResolverHandler<
  AdapterEnv extends ResolverEnv,
  AdapterContext,
>(
  options: Required<
    CreateMediaResolverHandlerOptions<AdapterEnv, AdapterContext>
  >,
): MediaResolverHandler<AdapterEnv, AdapterContext>;
export function createMediaResolverHandler<
  AdapterEnv extends ResolverEnv,
  AdapterContext,
>(
  options: CreateMediaResolverHandlerOptions<
    AdapterEnv,
    AdapterContext
  > = {},
): MediaResolverHandler<AdapterEnv, AdapterContext> {
  return {
    async fetch(
      request: Request,
      env: AdapterEnv,
      ctx: AdapterContext,
    ): Promise<Response> {
      const url = new URL(request.url);
      if (request.method === "GET" && url.pathname === "/health") {
        return Response.json({
          ok: true,
          service: "astrenza-media-resolver",
          version: env.SERVICE_VERSION,
        });
      }

      const runtime = runtimeForRequest(request, env, ctx, options);
      if (request.method === "GET" && url.pathname.startsWith("/v1/image/")) {
        return handleImage(request, env, runtime);
      }

      if (request.method === "POST" && url.pathname === "/v1/resolve") {
        return handleResolve(request, env, runtime);
      }

      return Response.json({ error: "not_found" }, { status: 404 });
    },
  };
}

function runtimeForRequest<AdapterEnv extends ResolverEnv, AdapterContext>(
  request: Request,
  env: AdapterEnv,
  ctx: AdapterContext,
  options: CreateMediaResolverHandlerOptions<AdapterEnv, AdapterContext>,
): RuntimeAdapter {
  if (options.runtimeAdapter) {
    return options.runtimeAdapter({ request, env, ctx });
  }

  return createCloudflareRuntimeAdapter({
    request,
    env,
    ctx: ctx as ExecutionContext,
  });
}

export default createMediaResolverHandler<
  ResolverEnv,
  ExecutionContext
>({
  runtimeAdapter: createCloudflareRuntimeAdapter,
}) satisfies ExportedHandler<ResolverEnv>;

async function handleImage(
  request: Request,
  env: ResolverEnv,
  runtime: RuntimeAdapter,
): Promise<Response> {
  const authError = await authorize(request, env);
  if (authError) return authError;

  const url = new URL(request.url);
  const preset = url.pathname.slice("/v1/image/".length);
  if (!isImagePresetName(preset)) {
    return jsonError("invalid_image_preset", 400);
  }

  const targetUrl = url.searchParams.get("url");
  if (!targetUrl) {
    return jsonError("missing_url", 400);
  }

  const imageTransformer = runtime.imageTransformer ?? fetchCloudflareImage;
  const result = await imageTransformer(request, targetUrl, preset, {
    fetch: runtime.fetch,
    serviceOrigin: runtime.serviceOrigin,
  });
  if (!result.ok) {
    return jsonError(result.error, result.status);
  }

  return result.response;
}

async function handleResolve(
  request: Request,
  env: ResolverEnv,
  runtime: RuntimeAdapter,
): Promise<Response> {
  const authError = await authorize(request, env);
  if (authError) return authError;

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return jsonError("invalid_json", 400);
  }

  if (!isResolveRequestBody(body)) {
    return jsonError("invalid_request", 400);
  }

  const imagePreset = body.imagePreset ?? "timeline";
  const context: ResolveContext = {
    fetch: runtime.fetch,
    cache: runtime.metaCache,
    cacheTtlSeconds: runtime.limits.cacheTtlSeconds,
    imageTransformer: runtime.imageTransformer,
    imagePreset,
    maxHtmlBytes: runtime.limits.maxHtmlBytes,
    maxImageProbeBytes: runtime.limits.maxImageProbeBytes,
    schedule: runtime.schedule,
    serviceOrigin: runtime.serviceOrigin,
  };

  const results: ResolveResult[] = [];
  for (const item of body.items) {
    results.push(await resolveItem(item, context));
  }

  return Response.json({ results });
}

async function authorize(
  request: Request,
  env: ResolverEnv,
): Promise<Response | null> {
  if (!bearerToken(request)) {
    return jsonError("missing_authorization", 401);
  }

  if (!env.ASTRENZA_SERVICE_TOKEN) {
    return jsonError("service_token_not_configured", 500);
  }

  if (!(await verifyBearerToken(request, env.ASTRENZA_SERVICE_TOKEN))) {
    return jsonError("invalid_authorization", 403);
  }

  return null;
}

async function resolveItem(
  item: ResolveItem,
  context: ResolveContext,
): Promise<ResolveResult> {
  const guard = validateFetchUrl(item.url, {
    serviceOrigin: context.serviceOrigin,
  });
  const inferredKind = inferResolveKind(item, guard.ok ? guard.url : item.url);
  if (!guard.ok) {
    return failedResult(item, item.url, item.url, inferredKind, guard.error);
  }

  const cached = await readResolveCache(
    context.cache,
    guard.url,
    context.imagePreset,
  );
  if (cached) {
    return { ...cached, id: item.id };
  }

  let result: ResolveResult;
  try {
    result = await resolveGuardedItem(item, guard.url, inferredKind, context);
  } catch (error) {
    result = failedResult(
      item,
      guard.url,
      guard.url,
      inferredKind,
      errorCode(error),
    );
  }

  writeResolveCache(
    context.schedule,
    context.cache,
    guard.url,
    context.imagePreset,
    result,
    context.cacheTtlSeconds,
  );
  return result;
}

async function resolveGuardedItem(
  item: ResolveItem,
  normalizedUrl: string,
  inferredKind: ResolveResult["kind"],
  context: ResolveContext,
): Promise<ResolveResult> {
  if (inferredKind === "image") {
    return resolveImageItem(item, normalizedUrl, context);
  }

  if (item.kind === "auto") {
    const autoImage = await resolveAutoImageItem(item, normalizedUrl, context);
    if (autoImage) return autoImage;
  }

  return resolveHtmlItem(item, normalizedUrl, context);
}

async function resolveImageItem(
  item: ResolveItem,
  normalizedUrl: string,
  context: ResolveContext,
): Promise<ResolveResult> {
  const resolved = await resolveImage(normalizedUrl, context, {
    failOnProbeError: true,
  });

  return {
    id: item.id,
    status: "resolved",
    kind: "image",
    url: normalizedUrl,
    finalUrl: normalizedUrl,
    title: null,
    description: null,
    siteName: null,
    thumbnailStyle: null,
    image: resolved.image,
    cacheTtlSeconds: context.cacheTtlSeconds,
    warnings: resolved.warnings,
    error: null,
  };
}

async function resolveAutoImageItem(
  item: ResolveItem,
  normalizedUrl: string,
  context: ResolveContext,
): Promise<ResolveResult | null> {
  let probe: Awaited<ReturnType<typeof probeImageHeader>>;
  try {
    probe = await probeImageHeader(normalizedUrl, {
      fetch: context.fetch,
      maxBytes: context.maxImageProbeBytes,
      timeoutMs: DEFAULT_IMAGE_PROBE_TIMEOUT_MS,
      serviceOrigin: context.serviceOrigin,
    });
  } catch {
    return null;
  }

  if (!probe.mimeType) return null;

  const blurhash = await generateBlurHash(normalizedUrl, {
    ...blurHashOptions(context),
    serviceOrigin: context.serviceOrigin,
  });

  return {
    id: item.id,
    status: "resolved",
    kind: "image",
    url: normalizedUrl,
    finalUrl: normalizedUrl,
    title: null,
    description: null,
    siteName: null,
    thumbnailStyle: null,
    image: {
      url: normalizedUrl,
      optimizedUrl: optimizedImageUrl(
        context.serviceOrigin,
        context.imagePreset,
        normalizedUrl,
      ),
      mimeType: probe.mimeType,
      width: probe.width,
      height: probe.height,
      blurhash: blurhash.blurhash,
    },
    cacheTtlSeconds: context.cacheTtlSeconds,
    warnings: [...probe.warnings, ...blurhash.warnings],
    error: null,
  };
}

async function resolveHtmlItem(
  item: ResolveItem,
  normalizedUrl: string,
  context: ResolveContext,
): Promise<ResolveResult> {
  const document = await fetchHtmlDocument(normalizedUrl, {
    fetch: context.fetch,
    maxBytes: context.maxHtmlBytes,
    serviceOrigin: context.serviceOrigin,
  });
  const metadata = await parseHtmlMetadata(document.html, document.finalUrl);
  const warnings: string[] = [...document.warnings];
  let image: ResolvedImage | null = null;

  if (metadata.image) {
    const resolvedImage = await resolveMetadataImage(metadata.image, context);
    image = resolvedImage.image;
    warnings.push(...resolvedImage.warnings);
  }

  return {
    id: item.id,
    status: "resolved",
    kind: "html",
    url: normalizedUrl,
    finalUrl: document.finalUrl,
    title: metadata.title,
    description: metadata.description,
    siteName: metadata.siteName,
    thumbnailStyle: metadata.thumbnailStyle,
    image,
    cacheTtlSeconds: context.cacheTtlSeconds,
    warnings,
    error: null,
  };
}

async function resolveMetadataImage(
  metadataImage: ResolvedImage,
  context: ResolveContext,
): Promise<ImageResolution> {
  try {
    const resolved = await resolveImage(metadataImage.url, context, {
      failOnProbeError: false,
      fallbackImage: metadataImage,
    });
    return resolved;
  } catch {
    return {
      image: {
        ...metadataImage,
        optimizedUrl: safeOptimizedImageUrl(metadataImage.url, context),
      },
      warnings: ["image_resolve_failed"],
    };
  }
}

async function resolveImage(
  imageUrl: string,
  context: ResolveContext,
  options: {
    failOnProbeError: boolean;
    fallbackImage?: ResolvedImage;
  },
): Promise<ImageResolution> {
  const guard = validateFetchUrl(imageUrl, {
    serviceOrigin: context.serviceOrigin,
  });
  if (!guard.ok) {
    if (options.failOnProbeError) {
      throw new Error(guard.error);
    }

    return {
      image: {
        ...(options.fallbackImage ?? emptyImage(imageUrl)),
        optimizedUrl: null,
      },
      warnings: [guard.error],
    };
  }

  const warnings: string[] = [];
  const image: ResolvedImage = {
    ...(options.fallbackImage ?? emptyImage(guard.url)),
    url: guard.url,
    optimizedUrl: optimizedImageUrl(
      context.serviceOrigin,
      context.imagePreset,
      guard.url,
    ),
  };

  try {
    const probe = await probeImageHeader(guard.url, {
      fetch: context.fetch,
      maxBytes: context.maxImageProbeBytes,
      timeoutMs: DEFAULT_IMAGE_PROBE_TIMEOUT_MS,
      serviceOrigin: context.serviceOrigin,
    });
    image.mimeType = probe.mimeType ?? image.mimeType;
    image.width = probe.width ?? image.width;
    image.height = probe.height ?? image.height;
    warnings.push(...probe.warnings);
  } catch (error) {
    if (options.failOnProbeError) throw error;
    warnings.push(errorCode(error));
  }

  const blurhash = await generateBlurHash(guard.url, {
    ...blurHashOptions(context),
    serviceOrigin: context.serviceOrigin,
  });
  image.blurhash = blurhash.blurhash;
  warnings.push(...blurhash.warnings);

  return { image, warnings };
}

function failedResult(
  item: ResolveItem,
  normalizedUrl: string,
  finalUrl: string,
  kind: ResolveResult["kind"],
  error: string,
): ResolveResult {
  return {
    id: item.id,
    status: "failed",
    kind,
    url: normalizedUrl,
    finalUrl,
    title: null,
    description: null,
    siteName: null,
    thumbnailStyle: null,
    image: null,
    cacheTtlSeconds: FAILED_CACHE_TTL_SECONDS,
    warnings: [],
    error,
  };
}

function emptyImage(url: string): ResolvedImage {
  return {
    url,
    optimizedUrl: null,
    mimeType: null,
    width: null,
    height: null,
    blurhash: null,
  };
}

function safeOptimizedImageUrl(
  imageUrl: string,
  context: ResolveContext,
): string | null {
  const guard = validateFetchUrl(imageUrl, {
    serviceOrigin: context.serviceOrigin,
  });
  if (!guard.ok) return null;

  return optimizedImageUrl(
    context.serviceOrigin,
    context.imagePreset,
    guard.url,
  );
}

function blurHashOptions(
  context: ResolveContext,
): Pick<GenerateBlurHashOptions, "fetch" | "fetchBlurHashSource"> {
  return {
    fetch: context.fetch,
    fetchBlurHashSource: context.imageTransformer
      ? (url, signal) => fetchBlurHashSource(context, url, signal)
      : undefined,
  };
}

async function fetchBlurHashSource(
  context: ResolveContext,
  url: string,
  signal: AbortSignal,
): Promise<Response> {
  const transformer = context.imageTransformer;
  if (!transformer) throw new Error("missing_image_transformer");

  const requestUrl = new URL("/v1/image/blurhash-source", context.serviceOrigin);
  requestUrl.searchParams.set("url", url);
  const request = new Request(requestUrl, {
    headers: { Accept: "image/jpeg" },
    signal,
  });
  const result = await transformer(request, url, "blurhash-source", {
    fetch: context.fetch,
    serviceOrigin: context.serviceOrigin,
  });
  if (!result.ok) throw new Error(result.error);
  return result.response;
}

function inferResolveKind(
  item: ResolveItem,
  normalizedUrl: string,
): ResolveResult["kind"] {
  if (item.kind === "html") return "html";
  if (item.kind === "image") return "image";
  return looksLikeImageUrl(normalizedUrl) ? "image" : "unknown";
}

function looksLikeImageUrl(rawUrl: string): boolean {
  try {
    const url = new URL(rawUrl);
    return /\.(?:avif|gif|jpe?g|png|webp)$/i.test(url.pathname);
  } catch {
    return false;
  }
}

function errorCode(error: unknown): string {
  if (error instanceof FetchHtmlError || error instanceof ImageProbeError) {
    return error.code;
  }

  if (error instanceof Error && error.message) {
    return error.message;
  }

  return "resolve_failed";
}

function isResolveRequestBody(body: unknown): body is ResolveBatchRequest {
  if (typeof body !== "object" || body === null) return false;
  const candidate = body as Partial<ResolveBatchRequest>;
  if (
    candidate.imagePreset !== undefined &&
    !isImagePresetName(candidate.imagePreset)
  ) {
    return false;
  }

  if (!Array.isArray(candidate.items)) return false;
  if (candidate.items.length > 20) return false;
  return candidate.items.every(isResolveItem);
}

function isResolveItem(value: unknown): value is ResolveItem {
  if (typeof value !== "object" || value === null) return false;
  const candidate = value as Partial<ResolveItem>;
  return (
    typeof candidate.id === "string" &&
    candidate.id.length > 0 &&
    typeof candidate.url === "string" &&
    candidate.url.length > 0 &&
    (candidate.kind === "auto" ||
      candidate.kind === "html" ||
      candidate.kind === "image")
  );
}

function jsonError(error: string, status: number): Response {
  return Response.json({ error }, { status });
}
