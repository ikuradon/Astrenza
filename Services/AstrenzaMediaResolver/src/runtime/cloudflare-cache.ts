import type { ResolveResult } from "../core/schema";
import type { ImagePresetName } from "./cloudflare-image";

export type MetaCacheBinding = Pick<KVNamespace, "get" | "put">;

export const FALLBACK_CACHE_TTL_SECONDS = 86400;
export const FAILED_CACHE_TTL_SECONDS = 1800;

const encoder = new TextEncoder();

export function defaultCacheTtlSeconds(rawValue: string | undefined): number {
  const parsed = Number(rawValue);
  if (!Number.isSafeInteger(parsed) || parsed <= 0) {
    return FALLBACK_CACHE_TTL_SECONDS;
  }
  return parsed;
}

export async function resolveCacheKey(
  normalizedUrl: string,
  imagePreset: ImagePresetName,
): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    encoder.encode(`${normalizedUrl}\n${imagePreset}`),
  );

  return `resolve:v1:${hexDigest(digest)}`;
}

export async function readResolveCache(
  cache: MetaCacheBinding | undefined,
  normalizedUrl: string,
  imagePreset: ImagePresetName,
): Promise<ResolveResult | null> {
  if (!cache) return null;

  const key = await resolveCacheKey(normalizedUrl, imagePreset);
  let value: string | null;
  try {
    value = await cache.get(key);
  } catch {
    return null;
  }
  if (!value) return null;

  try {
    const parsed = JSON.parse(value) as unknown;
    return isResolveResult(parsed) ? parsed : null;
  } catch {
    return null;
  }
}

export function writeResolveCache(
  ctx: ExecutionContext,
  cache: MetaCacheBinding | undefined,
  normalizedUrl: string,
  imagePreset: ImagePresetName,
  result: ResolveResult,
  resolvedTtlSeconds: number,
): void {
  if (!cache) return;

  const ttl =
    result.status === "resolved" ? resolvedTtlSeconds : FAILED_CACHE_TTL_SECONDS;
  ctx.waitUntil(
    writeResolveCacheNow(cache, normalizedUrl, imagePreset, result, ttl),
  );
}

async function writeResolveCacheNow(
  cache: MetaCacheBinding,
  normalizedUrl: string,
  imagePreset: ImagePresetName,
  result: ResolveResult,
  expirationTtl: number,
): Promise<void> {
  const key = await resolveCacheKey(normalizedUrl, imagePreset);
  await cache.put(key, JSON.stringify(result), { expirationTtl });
}

function hexDigest(buffer: ArrayBuffer): string {
  return Array.from(new Uint8Array(buffer), (byte) =>
    byte.toString(16).padStart(2, "0"),
  ).join("");
}

function isResolveResult(value: unknown): value is ResolveResult {
  if (typeof value !== "object" || value === null) return false;
  const candidate = value as Partial<ResolveResult>;
  return (
    typeof candidate.id === "string" &&
    (candidate.status === "resolved" || candidate.status === "failed") &&
    typeof candidate.url === "string" &&
    typeof candidate.finalUrl === "string" &&
    typeof candidate.cacheTtlSeconds === "number" &&
    Array.isArray(candidate.warnings)
  );
}
