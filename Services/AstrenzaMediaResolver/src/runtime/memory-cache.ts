import type { MetaCacheBinding, MetaCachePutOptions } from "./cloudflare-cache";

type InMemoryMetaCacheOptions = {
  now?: () => number;
};

type CacheEntry = {
  value: string;
  expiresAt: number | null;
};

export class InMemoryMetaCache implements MetaCacheBinding {
  private readonly values = new Map<string, CacheEntry>();
  private readonly now: () => number;

  constructor(options: InMemoryMetaCacheOptions = {}) {
    this.now = options.now ?? (() => Date.now());
  }

  async get(key: string): Promise<string | null> {
    const entry = this.values.get(key);
    if (!entry) return null;

    if (entry.expiresAt !== null && entry.expiresAt <= this.now()) {
      this.values.delete(key);
      return null;
    }

    return entry.value;
  }

  async put(
    key: string,
    value: string,
    options: MetaCachePutOptions = {},
  ): Promise<void> {
    this.values.set(key, {
      value,
      expiresAt: expirationTime(this.now(), options.expirationTtl),
    });
  }
}

function expirationTime(
  now: number,
  ttlSeconds: number | undefined,
): number | null {
  if (ttlSeconds === undefined) return null;
  if (!Number.isFinite(ttlSeconds) || ttlSeconds <= 0) return now;
  return now + ttlSeconds * 1000;
}
