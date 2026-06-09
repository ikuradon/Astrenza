import { MAX_HTML_BYTES } from "../core/html-metadata";
import { MAX_IMAGE_PROBE_BYTES } from "../core/image-header";
import {
  defaultCacheTtlSeconds,
  type BackgroundScheduler,
  type MetaCacheBinding,
} from "./cloudflare-cache";
import {
  fetchCloudflareImage,
  type CloudflareImageResult,
  type ImagePresetName,
} from "./cloudflare-image";

export type RuntimeLimits = {
  cacheTtlSeconds: number;
  maxHtmlBytes: number;
  maxImageProbeBytes: number;
};

export type ImageTransformOptions = {
  fetch: typeof fetch;
  serviceOrigin: string;
};

export type ImageTransformer = (
  request: Request,
  targetUrl: string,
  preset: ImagePresetName,
  options: ImageTransformOptions,
) => Promise<CloudflareImageResult>;

export type RuntimeAdapter = {
  fetch: typeof fetch;
  metaCache?: MetaCacheBinding;
  imageTransformer?: ImageTransformer;
  serviceOrigin: string;
  limits: RuntimeLimits;
  schedule: BackgroundScheduler;
};

export type RuntimeAdapterFactory<
  AdapterEnv = unknown,
  AdapterContext = unknown,
> = (args: {
  request: Request;
  env: AdapterEnv;
  ctx: AdapterContext;
}) => RuntimeAdapter;

export type CloudflareRuntimeEnv = {
  DEFAULT_CACHE_TTL_SECONDS?: string;
  MAX_HTML_BYTES?: string;
  MAX_IMAGE_PROBE_BYTES?: string;
  META_CACHE?: MetaCacheBinding;
};

export function createCloudflareRuntimeAdapter<
  AdapterEnv extends CloudflareRuntimeEnv,
>(
  args: {
    request: Request;
    env: AdapterEnv;
    ctx: ExecutionContext;
  },
): RuntimeAdapter {
  return {
    fetch,
    metaCache: args.env.META_CACHE,
    imageTransformer: fetchCloudflareImage,
    serviceOrigin: new URL(args.request.url).origin,
    limits: {
      cacheTtlSeconds: defaultCacheTtlSeconds(
        args.env.DEFAULT_CACHE_TTL_SECONDS,
      ),
      maxHtmlBytes: positiveEnvInteger(args.env.MAX_HTML_BYTES, MAX_HTML_BYTES),
      maxImageProbeBytes: positiveEnvInteger(
        args.env.MAX_IMAGE_PROBE_BYTES,
        MAX_IMAGE_PROBE_BYTES,
      ),
    },
    schedule(task) {
      args.ctx.waitUntil(task);
    },
  };
}

function positiveEnvInteger(
  rawValue: string | undefined,
  fallback: number,
): number {
  const parsed = Number(rawValue);
  if (!Number.isSafeInteger(parsed) || parsed <= 0) {
    return fallback;
  }
  return parsed;
}
