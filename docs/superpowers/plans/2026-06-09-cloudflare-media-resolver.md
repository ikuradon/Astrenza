# Cloudflare Media Resolver Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cloudflare-first の serverless service で OGP 解決、画像サイズ取得、BlurHash 生成、画像圧縮 proxy を行い、Astrenza client は service URL と token を設定して通信量を抑えた media 表示へ切り替える。

**Architecture:** `Services/AstrenzaMediaResolver` に TypeScript Worker service を追加し、metadata/URL/auth/HTML parsing/BlurHash 生成を runtime 非依存 core に置く。Cloudflare runtime では Workers KV と Cache API、Cloudflare Image Transformations を使い、Deno/self-host は同じ core に adapter を差し替える。iOS 側は既存 `NostrLinkPreviewResolver` と `media_assets` を拡張し、service 未設定時は既存 local fetch に fallback する。

**Tech Stack:** Cloudflare Workers, TypeScript, Vitest, @cloudflare/vitest-pool-workers, Workers KV, Cache API, Cloudflare Image Transformations, pure TypeScript image header parser, `blurhash`, `jpeg-js`, Swift 6.1, GRDB, Keychain Services.

---

## 0. 参照済み設計材料

- `ocknamo/nostr-image-optimizer`: Cloudflare Worker 上で remote image を fetch し、`width/height/quality/format` を guard して画像変換し、`Cache-Control` を強く付ける設計が参考になる。採用する点は preset/quality guard と cache header。採用しない点は token なし公開 proxy。
- `concrnt/hyperproxy`: `/summary` と `/image/*` を分け、private CIDR deny、memcache/disk cache、singleflight、Prometheus/trace を持つ。採用する点は summary/image 分離、deny CIDR、cache key の hash 化、観測性。Cloudflare Worker では DNS lookup が直接できないため、Cloudflare adapter は IP literal と redirect guard、self-host adapter は DNS lookup + CIDR deny を実装する。
- `misskey-dev/summaly`: `title/icon/description/thumbnail/player/sensitive/activityPub/fediverseCreator/url` の返却 schema、`responseTimeout`、`operationTimeout`、`contentLengthLimit`、local IP reject が参考になる。採用する点は timeout/content-length guard、nullable field、`thumbnailStyle`、local IP reject の思想。
- Cloudflare Workers best practices: `compatibility_date` を現日付で固定、`nodejs_compat`、`wrangler types`、secret は `wrangler secret put`、large body は bounded read、非同期 cache 書き込みは `ctx.waitUntil`、binding を直接使う。
- Cloudflare Image Transformations via Workers: `fetch(imageURL, { cf: { image: ... } })` で resize/format/quality を行う。source URL と Worker route の loop は検出する。
- Swift security: token は `UserDefaults` に置かない。service URL は `AppStorage`、token は Keychain actor に保存し、`Authorization: Bearer` は request 作成時だけ付与する。

## 1. File Structure

### New service files

- Create: `Services/AstrenzaMediaResolver/package.json`
  - Worker service の scripts と dependencies。
- Create: `Services/AstrenzaMediaResolver/wrangler.jsonc`
  - Worker entry、compatibility date、`nodejs_compat`、observability。KV binding は Task 5 で namespace 作成後に追加する。
- Create: `Services/AstrenzaMediaResolver/src/index.ts`
  - Cloudflare Worker entry。routing、auth、runtime adapter 接続だけを持つ。
- Create: `Services/AstrenzaMediaResolver/src/core/schema.ts`
  - request/response 型、normalization、JSON validation。
- Create: `Services/AstrenzaMediaResolver/src/core/auth.ts`
  - bearer token 抽出、SHA-256 hash、constant-time compare。
- Create: `Services/AstrenzaMediaResolver/src/core/url-guard.ts`
  - URL validation、IP literal/private range deny、redirect URL validation。
- Create: `Services/AstrenzaMediaResolver/src/core/html-metadata.ts`
  - OGP/Twitter Card/oEmbed link の streaming metadata extraction。
- Create: `Services/AstrenzaMediaResolver/src/core/image-header.ts`
  - PNG/JPEG/WebP/AVIF の bounded header parse。
- Create: `Services/AstrenzaMediaResolver/src/core/blurhash.ts`
  - 32px JPEG pixels から BlurHash を生成する。
- Create: `Services/AstrenzaMediaResolver/src/runtime/cloudflare-cache.ts`
  - KV metadata cache と Cache API image cache helper。
- Create: `Services/AstrenzaMediaResolver/src/runtime/cloudflare-image.ts`
  - Cloudflare Image Transformations adapter。
- Create: `Services/AstrenzaMediaResolver/src/runtime/portable.ts`
  - Deno/self-host 用 interface。MVP では Cloudflare adapter の contract を固定する。
- Create: `Services/AstrenzaMediaResolver/test/*.test.ts`
  - auth、URL guard、metadata parser、image header parser、resolve endpoint。
- Create: `Services/AstrenzaMediaResolver/fixtures/`
  - 小さい PNG/JPEG/WebP fixture。実画像は license 付き generated fixture のみ置く。
- Create: `Services/AstrenzaMediaResolver/README.md`
  - deploy、secret、client settings、cost/cache presets。

### AstrenzaCore files

- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrLinkModels.swift`
  - link preview image metadata と optimized image URL を追加。
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrMediaModels.swift`
  - direct media の optimized URL、resolution metadata、error を追加。
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrLinkPreviewResolver.swift`
  - remote service client を追加し、未設定時は既存 local resolver を使う。
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrEventStore.swift`
  - migration、decode/upsert、unresolved media query、save media metadata を追加。
- Create: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrMediaResolverModels.swift`
  - service request/response Codable 型。
- Create: `Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrMediaResolverTests.swift`
  - Codable、migration、remote response mapping の tests。

### Astrenza app files

- Create: `Astrenza/Sources/AstrenzaApp/Nostr/NostrMediaProxySettings.swift`
  - `AppStorage` URL/enabled と Keychain token accessor。
- Create: `Astrenza/Sources/AstrenzaApp/Nostr/AstrenzaKeychainStore.swift`
  - actor-based Keychain add-or-update。
- Modify: `Astrenza/Sources/AstrenzaApp/Nostr/NostrImageCache.swift`
  - proxy URL 向け `Authorization` header injection。
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrRemoteDataCache.swift`
  - request decorator を受けられるようにする。
- Modify: `Astrenza/Sources/AstrenzaApp/Nostr/NostrHomeTimelineStore.swift`
  - link preview と direct media metadata を batch resolve する。
- Modify: `Astrenza/Sources/AstrenzaApp/Nostr/NostrTimelineMediaProjection.swift`
  - optimized URL、BlurHash、image dimensions を優先して `TimelineMedia` へ投影する。
- Modify: `Astrenza/Sources/AstrenzaApp/TimelineModels.swift`
  - `LinkPreview` に image metadata/blurhash を追加。
- Modify: `Astrenza/Sources/AstrenzaApp/Components/Timeline/TimelineAttachments.swift`
  - link preview 画像にも BlurHash placeholder を使う。
- Modify: `Astrenza/Sources/AstrenzaApp/Components/Settings/SettingsView.swift`
  - Media Resolver settings 画面を追加。

---

## 2. Service API Contract

### Authentication

All endpoints except `GET /health` require:

```http
Authorization: Bearer astrenza-local-token-example
```

Worker secret:

```text
ASTRENZA_SERVICE_TOKEN=astrenza-local-token-example
```

The Worker hashes both provided and expected token with SHA-256 and uses `crypto.subtle.timingSafeEqual` on fixed-size hashes. Direct string comparison is disallowed.

### Endpoints

`GET /health`

```json
{ "ok": true, "service": "astrenza-media-resolver", "version": "1" }
```

`POST /v1/resolve`

Request:

```json
{
  "items": [
    { "id": "link:0", "url": "https://example.com/post", "kind": "auto" },
    { "id": "media:0", "url": "https://example.com/image.jpg", "kind": "image" }
  ],
  "imagePreset": "timeline"
}
```

Response:

```json
{
  "results": [
    {
      "id": "link:0",
      "status": "resolved",
      "kind": "html",
      "url": "https://example.com/post",
      "finalUrl": "https://example.com/post",
      "title": "Example",
      "description": "Summary",
      "siteName": "example.com",
      "thumbnailStyle": "summary_large_image",
      "image": {
        "url": "https://example.com/og.jpg",
        "optimizedUrl": "https://media.example.com/v1/image/timeline?url=https%3A%2F%2Fexample.com%2Fog.jpg",
        "mimeType": "image/jpeg",
        "width": 1200,
        "height": 630,
        "blurhash": "LEHV6nWB2yk8pyo0adR*.7kCMdnj"
      },
      "cacheTtlSeconds": 86400,
      "warnings": []
    }
  ]
}
```

`GET /v1/image/:preset?url=...`

- `preset=timeline`: `width=900`, `quality=72`, `fit=scale-down`, `format=auto`.
- `preset=thumb`: `width=360`, `quality=68`, `fit=scale-down`, `format=auto`.
- `preset=blurhash-source`: `width=32`, `height=32`, `quality=60`, `format=jpeg`.

The endpoint validates token, validates target URL, uses Cloudflare Image Transformations, and returns only image responses. It sets:

```http
Cache-Control: public, max-age=86400, stale-while-revalidate=7200, stale-if-error=3600, s-maxage=1209600
Vary: Accept
```

### Non-goals for this plan

- 動画 transcode と duration extraction は入れない。
- Public unauthenticated CDN は作らない。
- Browser rendering は入れない。HTML metadata と oEmbed JSON までに限定する。
- Remote image upload/storage は入れない。R2 は初期では使わない。

---

## 3. Task Plan

### Task 1: Worker scaffold

**Files:**
- Create: `Services/AstrenzaMediaResolver/package.json`
- Create: `Services/AstrenzaMediaResolver/wrangler.jsonc`
- Create: `Services/AstrenzaMediaResolver/src/index.ts`
- Create: `Services/AstrenzaMediaResolver/test/health.test.ts`

- [ ] **Step 1: Add package manifest**

`Services/AstrenzaMediaResolver/package.json`:

```json
{
  "name": "@astrenza/media-resolver",
  "private": true,
  "type": "module",
  "scripts": {
    "dev": "wrangler dev",
    "deploy": "wrangler deploy",
    "typecheck": "tsc --noEmit",
    "test": "vitest run",
    "cf:test": "vitest run --config vitest.config.ts",
    "types": "wrangler types"
  },
  "dependencies": {
    "blurhash": "^2.0.5",
    "jpeg-js": "^0.4.4"
  },
  "devDependencies": {
    "@cloudflare/vitest-pool-workers": "^0.8.0",
    "@cloudflare/workers-types": "^4.20260601.0",
    "typescript": "^5.8.3",
    "vitest": "^3.2.0",
    "wrangler": "^4.0.0"
  }
}
```

- [ ] **Step 2: Add Wrangler config**

`Services/AstrenzaMediaResolver/wrangler.jsonc`:

```jsonc
{
  "name": "astrenza-media-resolver",
  "main": "src/index.ts",
  "compatibility_date": "2026-06-09",
  "compatibility_flags": ["nodejs_compat"],
  "vars": {
    "SERVICE_VERSION": "1",
    "DEFAULT_CACHE_TTL_SECONDS": "86400",
    "MAX_HTML_BYTES": "1048576",
    "MAX_IMAGE_PROBE_BYTES": "131072"
  },
  "observability": {
    "enabled": true,
    "logs": {
      "head_sampling_rate": 1
    },
    "traces": {
      "enabled": true,
      "head_sampling_rate": 0.01
    }
  }
}
```

Before deploy, set the token secret:

```bash
cd Services/AstrenzaMediaResolver
npx wrangler secret put ASTRENZA_SERVICE_TOKEN
npx wrangler types
```

- [ ] **Step 3: Add minimal health handler**

`Services/AstrenzaMediaResolver/src/index.ts`:

```ts
export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (request.method === "GET" && url.pathname === "/health") {
      return Response.json({
        ok: true,
        service: "astrenza-media-resolver",
        version: env.SERVICE_VERSION,
      });
    }
    return Response.json({ error: "not_found" }, { status: 404 });
  },
} satisfies ExportedHandler<Env>;
```

- [ ] **Step 4: Add health test**

`Services/AstrenzaMediaResolver/test/health.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import worker from "../src/index";

describe("health", () => {
  it("returns service status without auth", async () => {
    const response = await worker.fetch(
      new Request("https://media.example.com/health"),
      { SERVICE_VERSION: "1" } as Env,
      {} as ExecutionContext,
    );

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toMatchObject({
      ok: true,
      service: "astrenza-media-resolver",
      version: "1",
    });
  });
});
```

- [ ] **Step 5: Verify**

Run:

```bash
cd Services/AstrenzaMediaResolver
npm install
npm run typecheck
npm run test
```

Expected: typecheck succeeds and `health.test.ts` passes.

### Task 2: Auth and URL guard

**Files:**
- Create: `Services/AstrenzaMediaResolver/src/core/auth.ts`
- Create: `Services/AstrenzaMediaResolver/src/core/url-guard.ts`
- Modify: `Services/AstrenzaMediaResolver/src/index.ts`
- Test: `Services/AstrenzaMediaResolver/test/auth.test.ts`
- Test: `Services/AstrenzaMediaResolver/test/url-guard.test.ts`

- [ ] **Step 1: Write auth tests**

Cases:

- missing `Authorization` returns 401 for `/v1/resolve`.
- invalid bearer returns 403.
- valid bearer reaches route validation.
- comparison hashes both values before `timingSafeEqual`.

- [ ] **Step 2: Implement auth helper**

Implementation shape:

```ts
const encoder = new TextEncoder();

export function bearerToken(request: Request): string | null {
  const header = request.headers.get("Authorization");
  if (!header?.startsWith("Bearer ")) return null;
  return header.slice("Bearer ".length).trim();
}

export async function verifyBearerToken(
  request: Request,
  expectedToken: string,
): Promise<boolean> {
  const provided = bearerToken(request);
  if (!provided) return false;

  const [providedHash, expectedHash] = await Promise.all([
    crypto.subtle.digest("SHA-256", encoder.encode(provided)),
    crypto.subtle.digest("SHA-256", encoder.encode(expectedToken)),
  ]);

  return crypto.subtle.timingSafeEqual(providedHash, expectedHash);
}
```

- [ ] **Step 3: Write URL guard tests**

Cases:

- allows `https://example.com/image.jpg`.
- rejects `file:`, `ftp:`, empty host, username/password URLs.
- rejects `127.0.0.1`, `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`, `169.254.0.0/16`, `::1`, `fc00::/7`, `fe80::/10`.
- rejects `localhost`, `.localhost`, `.local`, `.internal`.
- rejects recursive requests when target origin equals service origin.
- validates each redirect `Location` before following.

- [ ] **Step 4: Implement URL guard**

Implementation requirements:

- Use `new URL(raw)` once and normalize.
- Allow only `http:` and `https:`.
- Strip fragment from cache key.
- Block IP literal private ranges with explicit IPv4/IPv6 functions.
- In Cloudflare adapter, document that DNS-result private IP filtering is not available from Worker core; self-host adapter must add DNS lookup guard.

- [ ] **Step 5: Verify**

Run:

```bash
cd Services/AstrenzaMediaResolver
npm run typecheck
npm run test
```

Expected: auth and URL guard tests pass.

### Task 3: Metadata extraction

**Files:**
- Create: `Services/AstrenzaMediaResolver/src/core/schema.ts`
- Create: `Services/AstrenzaMediaResolver/src/core/html-metadata.ts`
- Test: `Services/AstrenzaMediaResolver/test/html-metadata.test.ts`

- [ ] **Step 1: Define schema**

Core result type:

```ts
export type ResolveItem = {
  id: string;
  url: string;
  kind: "auto" | "html" | "image";
};

export type ResolvedImage = {
  url: string;
  optimizedUrl: string | null;
  mimeType: string | null;
  width: number | null;
  height: number | null;
  blurhash: string | null;
};

export type ResolveResult = {
  id: string;
  status: "resolved" | "failed";
  kind: "html" | "image" | "unknown";
  url: string;
  finalUrl: string;
  title: string | null;
  description: string | null;
  siteName: string | null;
  thumbnailStyle: "summary" | "summary_large_image" | null;
  image: ResolvedImage | null;
  cacheTtlSeconds: number;
  warnings: string[];
  error: string | null;
};
```

- [ ] **Step 2: Write parser tests**

Fixtures:

- OGP with `og:title`, `og:description`, `og:site_name`, `og:image`, `og:image:width`, `og:image:height`.
- Twitter card fallback with `twitter:title`, `twitter:description`, `twitter:image`, `twitter:card`.
- `<title>` fallback.
- relative image URL resolution against final URL.
- oEmbed discovery via `<link rel="alternate" type="application/json+oembed">`.

- [ ] **Step 3: Implement bounded HTML fetch strategy**

Rules:

- Set `Accept: text/html,application/xhtml+xml`.
- Set `User-Agent: AstrenzaMediaResolver/1.0`.
- Use `AbortSignal.timeout(8000)`.
- Reject non-2xx.
- Reject `Content-Type` that is clearly not HTML for html mode.
- Read at most `MAX_HTML_BYTES`; if the stream exceeds the limit, stop and parse what was read with warning `html_truncated`.

- [ ] **Step 4: Implement metadata parser**

Use `HTMLRewriter` in Cloudflare runtime for `meta`, `title`, and `link` tags. For portable tests, keep a string parser fallback that is used by unit tests and Deno/self-host adapters.

- [ ] **Step 5: Verify**

Run:

```bash
cd Services/AstrenzaMediaResolver
npm run test -- html-metadata
```

Expected: parser returns deterministic nullable fields and absolute image URLs.

### Task 4: Image dimensions and BlurHash

**Files:**
- Create: `Services/AstrenzaMediaResolver/src/core/image-header.ts`
- Create: `Services/AstrenzaMediaResolver/src/core/blurhash.ts`
- Create: `Services/AstrenzaMediaResolver/test/image-header.test.ts`
- Create: `Services/AstrenzaMediaResolver/test/blurhash.test.ts`
- Create: `Services/AstrenzaMediaResolver/fixtures/tiny.png`
- Create: `Services/AstrenzaMediaResolver/fixtures/tiny.jpg`
- Create: `Services/AstrenzaMediaResolver/fixtures/tiny.webp`

- [ ] **Step 1: Implement header parser tests**

Expected:

- PNG parser reads IHDR width/height.
- JPEG parser scans SOF0/SOF2 and ignores APP/EXIF segments.
- WebP parser handles VP8X and VP8L dimensions.
- Unsupported or truncated buffers return `{ width: null, height: null, mimeType: null }`.

- [ ] **Step 2: Implement bounded probe fetch**

Rules:

- Use `HEAD` first when available to check `Content-Type` and `Content-Length`.
- Use `GET` with `Range: bytes=0-131071` for header probe.
- Do not read more than `MAX_IMAGE_PROBE_BYTES`.
- If server ignores Range and response grows beyond limit, cancel stream and return warning `image_probe_truncated`.

- [ ] **Step 3: Implement BlurHash generation**

Cloudflare-first path:

1. Fetch target image through Cloudflare Image Transformations as `width=32`, `height=32`, `fit=scale-down`, `format=jpeg`, `quality=60`.
2. Decode JPEG bytes with `jpeg-js`.
3. Encode RGBA pixels with `blurhash.encode(pixels, width, height, 4, 3)`.

Failure behavior:

- If transform fails, return `blurhash: null` and warning `blurhash_failed`.
- If decode fails, return `blurhash: null` and warning `blurhash_decode_failed`.
- Do not fail the whole resolve for missing BlurHash.

- [ ] **Step 4: Verify**

Run:

```bash
cd Services/AstrenzaMediaResolver
npm run test -- image-header
npm run test -- blurhash
```

Expected: fixture dimensions match and generated BlurHash decodes in tests.

### Task 5: Cloudflare image endpoint and metadata cache

**Files:**
- Create: `Services/AstrenzaMediaResolver/src/runtime/cloudflare-cache.ts`
- Create: `Services/AstrenzaMediaResolver/src/runtime/cloudflare-image.ts`
- Modify: `Services/AstrenzaMediaResolver/src/index.ts`
- Test: `Services/AstrenzaMediaResolver/test/image-endpoint.test.ts`
- Test: `Services/AstrenzaMediaResolver/test/resolve-endpoint.test.ts`

- [ ] **Step 1: Implement image presets**

Preset map:

```ts
export const imagePresets = {
  timeline: { width: 900, quality: 72, fit: "scale-down" },
  thumb: { width: 360, quality: 68, fit: "scale-down" },
  "blurhash-source": { width: 32, height: 32, quality: 60, fit: "scale-down", format: "jpeg" },
} as const;
```

- [ ] **Step 2: Implement image endpoint**

Rules:

- `GET /v1/image/:preset?url=...`.
- Require auth.
- Reject unknown preset.
- Validate target URL.
- Reject recursive request loop.
- Set `Accept` negotiation: if client accepts AVIF, use `format=avif`; else if WebP, `format=webp`; else JPEG. `blurhash-source` always uses JPEG.
- Forward only safe headers: `Accept`, `Accept-Language`, `If-None-Match`, `If-Modified-Since`. Do not forward client `Authorization` to upstream.
- Return transform response body directly. Do not buffer image body in Worker.

- [ ] **Step 3: Implement metadata cache**

KV key:

```text
resolve:v1:<sha256(normalizedUrl + "\n" + imagePreset)>
```

Behavior:

- Create production and preview KV namespaces before adding `META_CACHE` binding:

```bash
cd Services/AstrenzaMediaResolver
npx wrangler kv namespace create META_CACHE
npx wrangler kv namespace create META_CACHE --preview
```

- Add the exact `id` and `preview_id` values printed by those commands to `Services/AstrenzaMediaResolver/wrangler.jsonc` under `kv_namespaces`.
- Cache resolved and failed results separately.
- Resolved TTL: `DEFAULT_CACHE_TTL_SECONDS`.
- Failed TTL: 1800 seconds.
- Store JSON in KV with expiration TTL.
- Use `ctx.waitUntil` only for cache writes that are not needed for the response.

- [ ] **Step 4: Implement batch resolve**

Rules:

- `POST /v1/resolve` accepts up to 20 items.
- Resolve items sequentially or with concurrency 3 to avoid upstream burst.
- Direct image URLs skip HTML metadata and produce `kind: "image"`.
- HTML URLs resolve metadata first, then resolve metadata image dimensions and BlurHash.
- Every result includes `optimizedUrl` for images when the service can serve it.
- One item failure does not fail the batch.

- [ ] **Step 5: Verify**

Run:

```bash
cd Services/AstrenzaMediaResolver
npm run typecheck
npm run test
```

Expected: auth, URL guard, parser, image endpoint, resolve endpoint tests pass.

### Task 6: Swift service models and DB migration

**Files:**
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrLinkModels.swift`
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrMediaModels.swift`
- Create: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrMediaResolverModels.swift`
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrEventStore.swift`
- Test: `Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrMediaResolverTests.swift`

- [ ] **Step 1: Extend link preview model**

Add optional fields:

```swift
public let imageWidth: Int?
public let imageHeight: Int?
public let imageBlurhash: String?
public let optimizedImageURL: String?
public let thumbnailStyle: String?
```

Initializer must accept all new fields. Existing call sites must pass `nil` until remote resolver supplies values.

- [ ] **Step 2: Extend media asset model**

Add optional fields:

```swift
public let optimizedURL: String?
public let resolvedAt: Int?
public let error: String?
```

Projection uses `optimizedURL` for display and preserves `url` as source URL.

- [ ] **Step 3: Add Codable service models**

Create `NostrMediaResolverModels.swift` with:

```swift
public struct NostrMediaResolveRequest: Codable, Equatable, Sendable {
    public let items: [Item]
    public let imagePreset: String

    public struct Item: Codable, Equatable, Sendable {
        public let id: String
        public let url: String
        public let kind: String
    }
}

public struct NostrMediaResolveResponse: Codable, Equatable, Sendable {
    public let results: [Result]

    public struct Result: Codable, Equatable, Sendable {
        public let id: String
        public let status: String
        public let kind: String
        public let url: String
        public let finalUrl: String
        public let title: String?
        public let description: String?
        public let siteName: String?
        public let thumbnailStyle: String?
        public let image: Image?
        public let cacheTtlSeconds: Int
        public let warnings: [String]
        public let error: String?
    }

    public struct Image: Codable, Equatable, Sendable {
        public let url: String
        public let optimizedUrl: String?
        public let mimeType: String?
        public let width: Int?
        public let height: Int?
        public let blurhash: String?
    }
}
```

- [ ] **Step 4: Add DB migrations**

Add migration names after `addLinkPreviews`:

```swift
migrator.registerMigration("addLinkPreviewImageMetadata") { db in
    try db.alter(table: "link_previews") { table in
        table.add(column: "image_width", .integer)
        table.add(column: "image_height", .integer)
        table.add(column: "image_blurhash", .text)
        table.add(column: "optimized_image_url", .text)
        table.add(column: "thumbnail_style", .text)
    }
}

migrator.registerMigration("addMediaAssetResolutionMetadata") { db in
    try db.alter(table: "media_assets") { table in
        table.add(column: "optimized_url", .text)
        table.add(column: "resolved_at", .integer)
        table.add(column: "error", .text)
    }
}
```

Update all `SELECT`, `INSERT`, `decode`, and `upsert` paths.

- [ ] **Step 5: Add unresolved media and save methods**

Methods:

```swift
public func unresolvedMediaAssets(limit: Int = 20) throws -> [NostrMediaAssetRecord]
public func saveMediaAssetMetadata(_ asset: NostrMediaAssetRecord) throws
```

Query only rows with `status = 'unresolved'` or `status = 'failed'` with stale `resolved_at`.

- [ ] **Step 6: Verify**

Run:

```bash
xcodebuild test -project Astrenza.xcodeproj -scheme AstrenzaCore -destination 'platform=iOS Simulator,name=iPhone 17'
```

Expected: migrations and Codable mapping tests pass.

### Task 7: Swift remote resolver and fallback

**Files:**
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrLinkPreviewResolver.swift`
- Create: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrRemoteMediaResolver.swift`
- Test: `Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrMediaResolverTests.swift`

- [ ] **Step 1: Add remote resolver type**

Responsibilities:

- Build `POST /v1/resolve`.
- Add `Authorization: Bearer`.
- Timeout 12 seconds.
- Decode response.
- Map link results to `NostrLinkPreviewRecord`.
- Map image results to `NostrMediaAssetRecord`.
- Return per-item failures instead of throwing away the whole batch.

- [ ] **Step 2: Preserve local fallback**

Behavior:

- If service URL is empty or token is missing, use current `NostrLinkPreviewResolver` local HTML fetch path.
- If remote returns 401/403, mark resolver disabled for the current app session and show settings-visible error state.
- If remote times out, save failed previews with short TTL and retry later.

- [ ] **Step 3: Verify mapping tests**

Test JSON:

```json
{
  "results": [
    {
      "id": "link:https://example.com",
      "status": "resolved",
      "kind": "html",
      "url": "https://example.com",
      "finalUrl": "https://example.com",
      "title": "Example",
      "description": "Summary",
      "siteName": "Example",
      "thumbnailStyle": "summary_large_image",
      "image": {
        "url": "https://example.com/og.jpg",
        "optimizedUrl": "https://media.example.com/v1/image/timeline?url=https%3A%2F%2Fexample.com%2Fog.jpg",
        "mimeType": "image/jpeg",
        "width": 1200,
        "height": 630,
        "blurhash": "LEHV6nWB2yk8pyo0adR*.7kCMdnj"
      },
      "cacheTtlSeconds": 86400,
      "warnings": [],
      "error": null
    }
  ]
}
```

Expected Swift record:

- `title == "Example"`
- `optimizedImageURL` equals service image URL.
- `imageWidth == 1200`
- `imageHeight == 630`
- `imageBlurhash` is non-nil.

### Task 8: Client settings and Keychain token storage

**Files:**
- Create: `Astrenza/Sources/AstrenzaApp/Nostr/AstrenzaKeychainStore.swift`
- Create: `Astrenza/Sources/AstrenzaApp/Nostr/NostrMediaProxySettings.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Components/Settings/SettingsView.swift`
- Test: app-level unit tests if current test target can import app module; otherwise cover Keychain actor with a small isolated test target in the Xcode project.

- [ ] **Step 1: Add Keychain actor**

Use `kSecClassGenericPassword`, service `com.astrenza.media-resolver`, account `service-token`, explicit `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, and add-or-update semantics. Handle `errSecSuccess`, `errSecDuplicateItem`, `errSecItemNotFound`, and `errSecInteractionNotAllowed`.

- [ ] **Step 2: Add settings model**

Fields:

```swift
@AppStorage("mediaResolver.isEnabled") var isEnabled: Bool
@AppStorage("mediaResolver.serviceURL") var serviceURLString: String
```

Token methods:

```swift
func loadToken() async throws -> String?
func saveToken(_ token: String) async throws
func deleteToken() async throws
```

- [ ] **Step 3: Add settings UI**

Add a `Media Resolver` row under `GENERAL`.

Screen fields:

- Enable toggle.
- Service URL text field.
- Token secure field.
- Test Connection button calling `GET /health` without token and `POST /v1/resolve` with token against `https://example.com`.
- Status label with last success/failure.

Do not display token after save. Show only `Configured` or `Not configured`.

- [ ] **Step 4: Verify manually**

Run app, open Settings, save service URL and token, close/reopen settings, verify:

- URL persists.
- Token status says configured.
- Token raw value is not in `UserDefaults`.

### Task 9: Authenticated image loading

**Files:**
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrRemoteDataCache.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Nostr/NostrImageCache.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Components/Timeline/TimelineAttachments.swift`

- [ ] **Step 1: Add request decorator**

`NostrRemoteDataCache` initializer:

```swift
public init(
    urlCache: URLCache = URLCache(
        memoryCapacity: 32 * 1024 * 1024,
        diskCapacity: 256 * 1024 * 1024,
        diskPath: "AstrenzaRemoteData"
    ),
    urlSessionConfiguration: URLSessionConfiguration = .default,
    requestDecorator: (@Sendable (URLRequest) -> URLRequest)? = nil
)
```

`request(for:cachePolicy:)` applies decorator after default cache headers.

- [ ] **Step 2: Configure image cache for proxy auth**

In app layer, if URL host matches configured service URL host and token exists:

```swift
request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
```

Do not add token to original remote URLs.

- [ ] **Step 3: Update cache lookup consistency**

Ensure `cachedData(for:)`, `data(for:)`, and `store(data:response:for:)` use the same decorated request so `URLCache` lookup works for authenticated proxy URLs.

- [ ] **Step 4: Verify**

Use a fake `URLProtocol` or injected `NostrRemoteDataCache` to assert:

- Service URL request has Authorization.
- Non-service URL request does not.
- Cached proxy image is returned with the same decorated request.

### Task 10: Timeline resolution and projection

**Files:**
- Modify: `Astrenza/Sources/AstrenzaApp/Nostr/NostrHomeTimelineStore.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Nostr/NostrTimelineMediaProjection.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/TimelineModels.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Components/Timeline/TimelineAttachments.swift`

- [ ] **Step 1: Batch link preview resolution**

Change `scheduleLinkPreviewResolution()` from one remote request per preview to a batch call up to 20 items when remote service is configured. Existing local resolver remains at smaller batch or serial fetch.

- [ ] **Step 2: Add direct media resolution scheduler**

Add `scheduleMediaMetadataResolution()`:

- Query `eventStore.unresolvedMediaAssets(limit: 20)`.
- Send image items to remote resolver in one batch.
- Save `width`, `height`, `blurhash`, `optimizedURL`, `resolvedAt`, `status`.
- Re-materialize entries after saves.

- [ ] **Step 3: Projection uses optimized URL**

`mediaTile` URL selection:

```swift
let displayURL = asset.optimizedURL.flatMap(URL.init(string:)) ?? URL(string: asset.url)
```

`MediaTile` should keep display URL only; source URL remains in DB.

- [ ] **Step 4: Link preview uses image BlurHash**

Extend `LinkPreview`:

```swift
let imageWidth: Int?
let imageHeight: Int?
let imageBlurhash: String?
```

`LinkPreviewHeroView` shows `BlurHashPlaceholderView` while remote image loads.

- [ ] **Step 5: Verify**

Tests:

- A link preview with optimized image URL displays optimized URL.
- A direct media asset with optimized URL displays optimized URL.
- If optimized URL is nil, original URL is used.
- BlurHash placeholder renders for link preview before image load.

### Task 11: Portability adapters

**Files:**
- Create: `Services/AstrenzaMediaResolver/src/runtime/portable.ts`
- Create: `Services/AstrenzaMediaResolver/src/runtime/deno.ts`
- Create: `Services/AstrenzaMediaResolver/src/runtime/selfhost.ts`
- Create: `Services/AstrenzaMediaResolver/README.md`

- [ ] **Step 1: Define adapter interfaces**

```ts
export type MetadataCache = {
  get(key: string): Promise<string | null>;
  put(key: string, value: string, ttlSeconds: number): Promise<void>;
};

export type ImageTransformer = {
  optimizedUrl(sourceUrl: string, preset: string, serviceOrigin: string): string;
  fetchTransformed(sourceUrl: string, preset: string, request: Request): Promise<Response>;
  fetchBlurhashSource(sourceUrl: string): Promise<ArrayBuffer>;
};

export type NetworkGuard = {
  validateBeforeFetch(sourceUrl: URL, serviceOrigin: string): Promise<void>;
  validateRedirect(sourceUrl: URL, serviceOrigin: string): Promise<void>;
};
```

- [ ] **Step 2: Deno adapter**

Scope:

- Uses Deno KV for metadata cache.
- Uses same auth/schema/url guard.
- Uses remote image transformer URL configured by `IMAGE_TRANSFORMER_BASE_URL`.
- Does not run Cloudflare Image Transformations.

- [ ] **Step 3: Self-host adapter**

Scope:

- Uses Redis or filesystem cache through a small `MetadataCache` implementation.
- Uses `sharp` or `imgproxy/imagor` as image transformer.
- Adds DNS lookup + private CIDR deny before every fetch, following summaly/hyperproxy pattern.

- [ ] **Step 4: README deployment matrix**

Document:

| Runtime | OGP | image size | BlurHash | image compression | DNS private IP deny |
| --- | --- | --- | --- | --- | --- |
| Cloudflare Workers | yes | yes | yes | Cloudflare Images | IP literal + redirect guard |
| Deno Deploy | yes | yes | yes if transformer provides small JPEG | remote transformer | IP literal + redirect guard |
| Self-host Node/Go | yes | yes | yes | imgproxy/imagor/sharp | DNS + CIDR deny |

### Task 12: End-to-end verification

**Files:**
- Modify: `Services/AstrenzaMediaResolver/README.md`
- Modify: `.maestro/README.md` if manual media settings flow is added later.

- [ ] **Step 1: Worker verification**

Run:

```bash
cd Services/AstrenzaMediaResolver
npm run typecheck
npm run test
npm run dev
```

Manual:

```bash
curl http://localhost:8787/health
curl -H 'Authorization: Bearer astrenza-local-token-example' \
  -H 'Content-Type: application/json' \
  --data '{"items":[{"id":"link:0","url":"https://example.com","kind":"auto"}],"imagePreset":"timeline"}' \
  http://localhost:8787/v1/resolve
```

Expected:

- `/health` returns ok.
- `/v1/resolve` returns a result array.
- Missing token returns 401.
- Invalid token returns 403.

- [ ] **Step 2: Swift test verification**

Run:

```bash
xcodebuild test -project Astrenza.xcodeproj -scheme AstrenzaCore -destination 'platform=iOS Simulator,name=iPhone 17'
```

Expected: model, migration, resolver mapping tests pass.

- [ ] **Step 3: App manual verification**

Steps:

1. Start Worker locally or deploy staging Worker.
2. Configure service URL and token in Settings.
3. Load a timeline containing a note with a normal web URL and a direct image URL.
4. Confirm link preview resolves with title, image dimensions, and BlurHash placeholder.
5. Confirm direct image uses service optimized URL and authenticated request.
6. Disable service in Settings.
7. Confirm local resolver fallback still shows basic link previews.

Expected:

- No token appears in logs.
- Client does not fetch original image URL when optimized URL is present.
- Timeline remains usable if service is unavailable.

---

## 4. Security and Cost Controls

- Require bearer token for all resolve/image endpoints.
- Store Worker token via `wrangler secret put`; store client token in Keychain.
- Do not put token in image query string.
- Do not forward client `Authorization` to upstream sites.
- Reject dangerous schemes, credentials in URL, local hostnames, IP literals in private ranges, and recursive service origin.
- Limit batch resolve to 20 items.
- Limit HTML read to 1 MiB.
- Limit image header probe to 128 KiB.
- Limit redirect count to 3.
- Cache resolved metadata for 24 hours, failed metadata for 30 minutes.
- Use only three image presets to avoid transformation cache fragmentation.
- Start without R2. Add R2 only if later requirements need persistent thumbnails or audit artifacts.

## 5. Self-review

- Spec coverage: OGP, image size, BlurHash, image compression, token-protected service URL settings, local communication reduction, Cloudflare-first, Deno/self-host portability are all mapped to tasks.
- Marker scan: no blocked implementation markers remain; environment-specific KV ids are produced by `wrangler kv namespace create` during Task 5.
- Type consistency: Worker response fields match Swift Codable fields. Link preview uses `optimizedImageURL`; media asset uses `optimizedURL`.
- Risk: Cloudflare Worker cannot perform DNS-result private CIDR inspection in the same way self-host can. The plan mitigates this with strict URL/IP literal/redirect guards and reserves full DNS CIDR deny for self-host adapter.
