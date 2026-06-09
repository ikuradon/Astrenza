import type { ResolvedImage } from "./schema";
import { validateFetchUrl, validateRedirectLocation } from "./url-guard";

export const MAX_HTML_BYTES = 256 * 1024;
export const DEFAULT_HTML_TIMEOUT_MS = 8000;
export const DEFAULT_MAX_REDIRECTS = 5;

export type ParsedHtmlMetadata = {
  title: string | null;
  description: string | null;
  siteName: string | null;
  thumbnailStyle: "summary" | "summary_large_image" | null;
  image: ResolvedImage | null;
  oEmbedUrl: string | null;
};

export type FetchHtmlWarning = "html_truncated";

export type FetchHtmlDocument = {
  html: string;
  finalUrl: string;
  warnings: FetchHtmlWarning[];
};

export type FetchHtmlErrorCode =
  | "unsafe_url"
  | "http_status"
  | "unsupported_content_type"
  | "missing_redirect_location"
  | "unsafe_redirect"
  | "too_many_redirects";

export class FetchHtmlError extends Error {
  readonly code: FetchHtmlErrorCode;
  readonly status?: number;
  readonly contentType?: string;
  readonly guardError?: string;

  constructor(
    code: FetchHtmlErrorCode,
    options: {
      status?: number;
      contentType?: string;
      guardError?: string;
    } = {},
  ) {
    super(code);
    this.name = "FetchHtmlError";
    this.code = code;
    this.status = options.status;
    this.contentType = options.contentType;
    this.guardError = options.guardError;
  }
}

export type FetchHtmlOptions = {
  fetch?: typeof fetch;
  maxBytes?: number;
  timeoutMs?: number;
  maxRedirects?: number;
  signal?: AbortSignal;
  serviceOrigin?: string;
};

export function parseHtmlMetadataString(
  html: string,
  finalUrl: string,
): ParsedHtmlMetadata {
  const collector = new HtmlMetadataCollector(finalUrl);

  for (const attributes of startTagAttributes(html, "meta")) {
    collector.addMeta(attributes);
  }

  for (const attributes of startTagAttributes(html, "link")) {
    collector.addLink(attributes);
  }

  const title = titleTagContent(html);
  if (title !== null) {
    collector.addTitleText(title);
  }

  return collector.toMetadata();
}

export async function parseHtmlMetadata(
  html: string,
  finalUrl: string,
): Promise<ParsedHtmlMetadata> {
  const Rewriter = (globalThis as { HTMLRewriter?: HtmlRewriterConstructor })
    .HTMLRewriter;
  if (!Rewriter) {
    return parseHtmlMetadataString(html, finalUrl);
  }

  const collector = new HtmlMetadataCollector(finalUrl);
  const rewriter = new Rewriter()
    .on("meta", {
      element(element) {
        collector.addMeta(attributesFromElement(element, [
          "property",
          "name",
          "content",
        ]));
      },
    })
    .on("link", {
      element(element) {
        collector.addLink(
          attributesFromElement(element, ["rel", "type", "href"]),
        );
      },
    })
    .on("title", {
      text(text) {
        collector.addTitleText(text.text);
      },
    });

  await rewriter
    .transform(
      new Response(html, {
        headers: { "Content-Type": "text/html; charset=utf-8" },
      }),
    )
    .arrayBuffer();

  return collector.toMetadata();
}

export async function fetchHtmlDocument(
  url: string,
  options: FetchHtmlOptions = {},
): Promise<FetchHtmlDocument> {
  const fetchImpl = options.fetch ?? fetch;
  const maxBytes = options.maxBytes ?? MAX_HTML_BYTES;
  const maxRedirects = options.maxRedirects ?? DEFAULT_MAX_REDIRECTS;
  const signal = combinedSignal(
    options.signal,
    options.timeoutMs ?? DEFAULT_HTML_TIMEOUT_MS,
  );

  const initialGuard = validateFetchUrl(url, {
    serviceOrigin: options.serviceOrigin,
  });
  if (!initialGuard.ok) {
    throw new FetchHtmlError("unsafe_url", {
      guardError: initialGuard.error,
    });
  }

  let currentUrl = initialGuard.url;
  for (let redirectCount = 0; redirectCount <= maxRedirects; redirectCount += 1) {
    const response = await fetchImpl(currentUrl, {
      headers: {
        Accept: "text/html,application/xhtml+xml",
        "User-Agent": "AstrenzaMediaResolver/1.0",
      },
      redirect: "manual",
      signal,
    });

    if (isRedirectStatus(response.status)) {
      if (redirectCount === maxRedirects) {
        await cancelResponseBody(response);
        throw new FetchHtmlError("too_many_redirects", {
          status: response.status,
        });
      }

      const location = response.headers.get("Location");
      if (!location) {
        await cancelResponseBody(response);
        throw new FetchHtmlError("missing_redirect_location", {
          status: response.status,
        });
      }

      const guard = validateRedirectLocation(location, new URL(currentUrl), {
        serviceOrigin: options.serviceOrigin,
      });
      if (!guard.ok) {
        await cancelResponseBody(response);
        throw new FetchHtmlError("unsafe_redirect", {
          status: response.status,
          guardError: guard.error,
        });
      }

      await cancelResponseBody(response);
      currentUrl = guard.url;
      continue;
    }

    if (!isSuccessStatus(response.status)) {
      await cancelResponseBody(response);
      throw new FetchHtmlError("http_status", { status: response.status });
    }

    const contentType = response.headers.get("Content-Type");
    if (isClearlyNotHtml(contentType)) {
      await cancelResponseBody(response);
      throw new FetchHtmlError("unsupported_content_type", { contentType });
    }

    const { html, warnings } = await readLimitedText(
      response,
      maxBytes,
      contentType,
    );
    return {
      html,
      finalUrl: currentUrl,
      warnings,
    };
  }

  throw new FetchHtmlError("too_many_redirects");
}

type HtmlRewriterConstructor = new () => HtmlRewriterLike;

type HtmlRewriterLike = {
  on(selector: string, handlers: HtmlRewriterHandlers): HtmlRewriterLike;
  transform(response: Response): Response;
};

type HtmlRewriterHandlers = {
  element?: (element: HtmlRewriterElementLike) => void;
  text?: (text: HtmlRewriterTextLike) => void;
};

type HtmlRewriterElementLike = {
  getAttribute(name: string): string | null;
};

type HtmlRewriterTextLike = {
  text: string;
};

class HtmlMetadataCollector {
  private readonly meta = new Map<string, string>();
  private readonly titleParts: string[] = [];
  private oEmbedHref: string | null = null;

  constructor(private readonly finalUrl: string) {}

  addMeta(attributes: Record<string, string>): void {
    const key = firstNonEmpty([
      attributes.property,
      attributes.name,
    ])?.toLowerCase();
    const content = cleanText(attributes.content);
    if (!key || content === null || this.meta.has(key)) return;

    this.meta.set(key, content);
  }

  addLink(attributes: Record<string, string>): void {
    if (this.oEmbedHref !== null) return;

    const rel = attributes.rel?.toLowerCase();
    const type = mediaType(attributes.type);
    const href = cleanText(attributes.href);
    if (!rel || !href) return;

    const relTokens = rel.split(/\s+/).filter(Boolean);
    if (!relTokens.includes("alternate")) return;
    if (type !== "application/json+oembed" && type !== "text/json+oembed") {
      return;
    }

    this.oEmbedHref = absoluteUrl(href, this.finalUrl);
  }

  addTitleText(text: string): void {
    this.titleParts.push(text);
  }

  toMetadata(): ParsedHtmlMetadata {
    const ogImage = firstNonEmpty([
      this.meta.get("og:image"),
      this.meta.get("og:image:url"),
    ]);
    const twitterImage = firstNonEmpty([
      this.meta.get("twitter:image"),
      this.meta.get("twitter:image:src"),
    ]);
    const imageUrl = absoluteUrl(ogImage ?? twitterImage, this.finalUrl);

    return {
      title: firstNonEmpty([
        this.meta.get("og:title"),
        this.meta.get("twitter:title"),
        cleanText(this.titleParts.join("")),
      ]),
      description: firstNonEmpty([
        this.meta.get("og:description"),
        this.meta.get("twitter:description"),
        this.meta.get("description"),
      ]),
      siteName: firstNonEmpty([this.meta.get("og:site_name")]),
      thumbnailStyle: thumbnailStyle(this.meta.get("twitter:card")),
      image: imageUrl
        ? {
            url: imageUrl,
            optimizedUrl: null,
            mimeType: null,
            width: ogImage ? positiveInteger(this.meta.get("og:image:width")) : null,
            height: ogImage
              ? positiveInteger(this.meta.get("og:image:height"))
              : null,
            blurhash: null,
          }
        : null,
      oEmbedUrl: this.oEmbedHref,
    };
  }
}

function* startTagAttributes(
  html: string,
  tagName: "meta" | "link",
): Generator<Record<string, string>> {
  const pattern = new RegExp(`<${tagName}\\b`, "gi");
  for (const match of html.matchAll(pattern)) {
    const start = (match.index ?? 0) + match[0].length;
    const end = startTagEndIndex(html, start);
    if (end === null) continue;

    yield parseAttributes(html.slice(start, end));
  }
}

function startTagEndIndex(html: string, start: number): number | null {
  let quote: '"' | "'" | null = null;

  for (let index = start; index < html.length; index += 1) {
    const char = html[index];
    if (quote !== null) {
      if (char === quote) quote = null;
      continue;
    }

    if (char === '"' || char === "'") {
      quote = char;
      continue;
    }

    if (char === ">") {
      return index;
    }
  }

  return null;
}

function parseAttributes(attributes: string): Record<string, string> {
  const result: Record<string, string> = {};
  const pattern =
    /([^\s"'<>/=]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+))/g;

  for (const match of attributes.matchAll(pattern)) {
    const name = match[1]?.toLowerCase();
    const value = match[2] ?? match[3] ?? match[4] ?? "";
    if (name) {
      result[name] = htmlDecode(value);
    }
  }

  return result;
}

function attributesFromElement(
  element: HtmlRewriterElementLike,
  names: string[],
): Record<string, string> {
  const result: Record<string, string> = {};
  for (const name of names) {
    const value = element.getAttribute(name);
    if (value !== null) {
      result[name] = htmlDecode(value);
    }
  }
  return result;
}

function titleTagContent(html: string): string | null {
  const match = /<title\b[^>]*>([\s\S]*?)<\/title>/i.exec(html);
  return match ? htmlDecode(match[1] ?? "") : null;
}

function cleanText(value: string | null | undefined): string | null {
  const trimmed = value?.trim();
  return trimmed ? trimmed : null;
}

function firstNonEmpty(values: Array<string | null | undefined>): string | null {
  for (const value of values) {
    const cleaned = cleanText(value);
    if (cleaned) return cleaned;
  }
  return null;
}

function thumbnailStyle(
  card: string | null | undefined,
): "summary" | "summary_large_image" | null {
  const normalized = card?.trim().toLowerCase();
  if (normalized === "summary" || normalized === "summary_large_image") {
    return normalized;
  }
  return null;
}

function positiveInteger(value: string | null | undefined): number | null {
  const cleaned = cleanText(value);
  if (!cleaned || !/^\d+$/.test(cleaned)) return null;

  const parsed = Number.parseInt(cleaned, 10);
  return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : null;
}

function absoluteUrl(
  raw: string | null | undefined,
  finalUrl: string,
): string | null {
  const cleaned = cleanText(raw);
  if (!cleaned) return null;

  try {
    return new URL(cleaned, finalUrl).href;
  } catch {
    return null;
  }
}

function mediaType(value: string | null | undefined): string | null {
  return cleanText(value)?.split(";")[0]?.trim().toLowerCase() ?? null;
}

function htmlDecode(value: string): string {
  return value
    .replace(/&#(\d+);/g, (_match, digits: string) =>
      numericEntity(Number.parseInt(digits, 10)),
    )
    .replace(/&#x([0-9a-f]+);/gi, (_match, digits: string) =>
      numericEntity(Number.parseInt(digits, 16)),
    )
    .replace(/&amp;/gi, "&")
    .replace(/&quot;/gi, '"')
    .replace(/&#39;/g, "'")
    .replace(/&#x27;/gi, "'")
    .replace(/&apos;/gi, "'")
    .replace(/&lt;/gi, "<")
    .replace(/&gt;/gi, ">");
}

function numericEntity(codePoint: number): string {
  if (!Number.isInteger(codePoint) || codePoint <= 0) return "";

  try {
    return String.fromCodePoint(codePoint);
  } catch {
    return "";
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

function isClearlyNotHtml(contentType: string | null): contentType is string {
  const type = mediaType(contentType);
  if (!type) return false;

  return type !== "text/html" && type !== "application/xhtml+xml";
}

async function readLimitedText(
  response: Response,
  maxBytes: number,
  contentType: string | null,
): Promise<{ html: string; warnings: FetchHtmlWarning[] }> {
  if (!response.body) {
    return { html: "", warnings: [] };
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
    }
  } finally {
    reader.releaseLock();
  }

  return {
    html: decodeBytes(concatChunks(chunks, bytesRead), contentType),
    warnings: truncated ? ["html_truncated"] : [],
  };
}

async function cancelResponseBody(response: Response): Promise<void> {
  try {
    await response.body?.cancel();
  } catch {
    // runtime 側で cancel できない場合も、返すエラーは揺らさない。
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

function decodeBytes(bytes: Uint8Array, contentType: string | null): string {
  const charset = charsetFromContentType(contentType);
  try {
    return new TextDecoder(charset ?? "utf-8").decode(bytes);
  } catch {
    return new TextDecoder("utf-8").decode(bytes);
  }
}

function charsetFromContentType(contentType: string | null): string | null {
  if (!contentType) return null;

  for (const part of contentType.split(";").slice(1)) {
    const [name, rawValue] = part.split("=", 2);
    if (name?.trim().toLowerCase() === "charset") {
      return rawValue?.trim().replace(/^["']|["']$/g, "") || null;
    }
  }

  return null;
}
