import { afterEach, describe, expect, it, vi } from "vitest";
import {
  FetchHtmlError,
  fetchHtmlDocument,
  parseHtmlMetadata,
  parseHtmlMetadataString,
} from "../src/core/html-metadata";

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("parseHtmlMetadataString", () => {
  it("prefers OGP metadata and reads image dimensions", () => {
    const result = parseHtmlMetadataString(
      `
        <html>
          <head>
            <title>Fallback title</title>
            <meta name="twitter:title" content="Twitter title">
            <meta property="og:title" content="OG title">
            <meta property="og:description" content="OG description">
            <meta property="og:site_name" content="Example News">
            <meta name="twitter:image" content="https://cdn.example.com/twitter.jpg">
            <meta property="og:image" content="https://cdn.example.com/cover.jpg">
            <meta property="og:image:width" content="1200">
            <meta property="og:image:height" content="630">
          </head>
        </html>
      `,
      "https://example.com/posts/1",
    );

    expect(result).toEqual({
      title: "OG title",
      description: "OG description",
      siteName: "Example News",
      thumbnailStyle: null,
      image: {
        url: "https://cdn.example.com/cover.jpg",
        optimizedUrl: null,
        mimeType: null,
        width: 1200,
        height: 630,
        blurhash: null,
      },
      oEmbedUrl: null,
    });
  });

  it("falls back to Twitter card metadata before the title tag", () => {
    const result = parseHtmlMetadataString(
      `
        <html>
          <head>
            <title>Plain title</title>
            <meta name="twitter:card" content="summary_large_image">
            <meta name="twitter:title" content="Twitter title">
            <meta name="twitter:description" content="Twitter description">
            <meta name="twitter:image" content="https://cdn.example.com/twitter.jpg">
          </head>
        </html>
      `,
      "https://example.com/posts/1",
    );

    expect(result).toEqual({
      title: "Twitter title",
      description: "Twitter description",
      siteName: null,
      thumbnailStyle: "summary_large_image",
      image: {
        url: "https://cdn.example.com/twitter.jpg",
        optimizedUrl: null,
        mimeType: null,
        width: null,
        height: null,
        blurhash: null,
      },
      oEmbedUrl: null,
    });
  });

  it("falls back to a decoded title tag", () => {
    const result = parseHtmlMetadataString(
      "<html><head><title>  A &amp; B  </title></head></html>",
      "https://example.com/posts/1",
    );

    expect(result).toEqual({
      title: "A & B",
      description: null,
      siteName: null,
      thumbnailStyle: null,
      image: null,
      oEmbedUrl: null,
    });
  });

  it("resolves relative image URLs against the final URL", () => {
    const result = parseHtmlMetadataString(
      '<meta property="og:image" content="../images/cover.jpg">',
      "https://example.com/posts/2026/item.html?from=nostr",
    );

    expect(result.image?.url).toBe("https://example.com/posts/images/cover.jpg");
  });

  it("discovers JSON oEmbed alternate links", () => {
    const result = parseHtmlMetadataString(
      `
        <link
          rel="preload alternate"
          type="application/json+oembed"
          href="/oembed?url=https%3A%2F%2Fexample.com%2Fposts%2F1"
        >
      `,
      "https://example.com/posts/1",
    );

    expect(result.oEmbedUrl).toBe(
      "https://example.com/oembed?url=https%3A%2F%2Fexample.com%2Fposts%2F1",
    );
  });

  it("keeps quoted greater-than characters inside metadata attributes", () => {
    const result = parseHtmlMetadataString(
      '<meta property="og:title" content="A > B">',
      "https://example.com/posts/1",
    );

    expect(result.title).toBe("A > B");
  });

  it("decodes numeric HTML entities", () => {
    const result = parseHtmlMetadataString(
      "<title>Tom &#8217; Jerry</title>",
      "https://example.com/posts/1",
    );

    expect(result.title).toBe(`Tom ${String.fromCharCode(8217)} Jerry`);
  });
});

describe("parseHtmlMetadata", () => {
  it("uses HTMLRewriter when available and joins title text chunks", async () => {
    class FakeHTMLRewriter {
      private titleHandler: ((text: { text: string }) => void) | undefined;

      on(
        selector: string,
        handlers: { text?: (text: { text: string }) => void },
      ): FakeHTMLRewriter {
        if (selector === "title") {
          this.titleHandler = handlers.text;
        }
        return this;
      }

      transform(response: Response): Response {
        this.titleHandler?.({ text: "Chunked " });
        this.titleHandler?.({ text: "Title" });
        return response;
      }
    }

    vi.stubGlobal("HTMLRewriter", FakeHTMLRewriter);

    const result = await parseHtmlMetadata(
      "<title>Fallback</title>",
      "https://example.com/posts/1",
    );

    expect(result.title).toBe("Chunked Title");
  });
});

describe("fetchHtmlDocument", () => {
  it("uses bounded HTML request headers and manually follows safe redirects", async () => {
    const calls: Array<{ input: RequestInfo | URL; init?: RequestInit }> = [];
    const fetchMock = vi.fn<typeof fetch>(async (input, init) => {
      calls.push({ input, init });
      if (calls.length === 1) {
        return new Response(null, {
          status: 302,
          headers: { Location: "/final" },
        });
      }
      return new Response("<html>ok</html>", {
        status: 200,
        headers: { "Content-Type": "text/html; charset=utf-8" },
      });
    });

    const result = await fetchHtmlDocument("https://example.com/start", {
      fetch: fetchMock,
    });

    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(calls[0]?.input).toBe("https://example.com/start");
    expect(calls[0]?.init?.headers).toEqual({
      Accept: "text/html,application/xhtml+xml",
      "User-Agent": "AstrenzaMediaResolver/1.0",
    });
    expect(calls[0]?.init?.redirect).toBe("manual");
    expect(calls[0]?.init?.signal).toBeInstanceOf(AbortSignal);
    expect(calls[1]?.input).toBe("https://example.com/final");
    expect(result).toEqual({
      html: "<html>ok</html>",
      finalUrl: "https://example.com/final",
      warnings: [],
    });
  });

  it("rejects non-2xx HTML responses", async () => {
    const fetchMock = vi.fn<typeof fetch>(async () => {
      return new Response("missing", {
        status: 404,
        headers: { "Content-Type": "text/html" },
      });
    });

    await expect(
      fetchHtmlDocument("https://example.com/missing", { fetch: fetchMock }),
    ).rejects.toMatchObject({
      code: "http_status",
      status: 404,
    } satisfies Partial<FetchHtmlError>);
  });

  it("rejects content types that are clearly not HTML", async () => {
    const fetchMock = vi.fn<typeof fetch>(async () => {
      return new Response("png", {
        status: 200,
        headers: { "Content-Type": "image/png" },
      });
    });

    await expect(
      fetchHtmlDocument("https://example.com/image", { fetch: fetchMock }),
    ).rejects.toMatchObject({
      code: "unsupported_content_type",
      contentType: "image/png",
    } satisfies Partial<FetchHtmlError>);
  });

  it("stops reading after the maximum HTML byte limit", async () => {
    const fetchMock = vi.fn<typeof fetch>(async () => {
      return new Response("0123456789EXTRA", {
        status: 200,
        headers: { "Content-Type": "text/html" },
      });
    });

    const result = await fetchHtmlDocument("https://example.com/large", {
      fetch: fetchMock,
      maxBytes: 10,
    });

    expect(result).toEqual({
      html: "0123456789",
      finalUrl: "https://example.com/large",
      warnings: ["html_truncated"],
    });
  });

  it("validates redirect locations before following them", async () => {
    const fetchMock = vi.fn<typeof fetch>(async () => {
      return new Response(null, {
        status: 302,
        headers: { Location: "http://127.0.0.1/private" },
      });
    });

    await expect(
      fetchHtmlDocument("https://example.com/start", { fetch: fetchMock }),
    ).rejects.toMatchObject({
      code: "unsafe_redirect",
      guardError: "blocked_private_address",
    } satisfies Partial<FetchHtmlError>);
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it("validates the initial URL before fetching", async () => {
    const fetchMock = vi.fn<typeof fetch>();

    await expect(
      fetchHtmlDocument("http://127.0.0.1/private", { fetch: fetchMock }),
    ).rejects.toMatchObject({
      code: "unsafe_url",
      guardError: "blocked_private_address",
    } satisfies Partial<FetchHtmlError>);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("combines caller cancellation with the timeout signal", async () => {
    const controller = new AbortController();
    let requestSignal: AbortSignal | undefined;
    const fetchMock = vi.fn<typeof fetch>(async (_input, init) => {
      requestSignal = init?.signal ?? undefined;
      return new Response("<html>ok</html>", {
        status: 200,
        headers: { "Content-Type": "text/html" },
      });
    });

    await fetchHtmlDocument("https://example.com/start", {
      fetch: fetchMock,
      signal: controller.signal,
    });

    expect(requestSignal).toBeInstanceOf(AbortSignal);
    expect(requestSignal).not.toBe(controller.signal);
  });
});
