import { describe, expect, it } from "vitest";
import {
  validateFetchUrl,
  validateRedirectLocation,
} from "../src/core/url-guard";

describe("validateFetchUrl", () => {
  it("allows https image URLs and strips fragments from the cache key", () => {
    const result = validateFetchUrl("https://example.com/image.jpg#preview");

    expect(result).toEqual({
      ok: true,
      url: "https://example.com/image.jpg",
      cacheKey: "https://example.com/image.jpg",
    });
  });

  it.each([
    "file:///etc/passwd",
    "ftp://example.com/image.jpg",
    "https://",
    "https://user:password@example.com/image.jpg",
  ])("rejects unsupported or credentialed URL %s", (rawUrl) => {
    const result = validateFetchUrl(rawUrl);

    expect(result.ok).toBe(false);
  });

  it.each([
    "https://127.0.0.1/image.jpg",
    "https://0.0.0.0/image.jpg",
    "https://10.0.0.1/image.jpg",
    "https://100.64.0.1/image.jpg",
    "https://172.16.0.1/image.jpg",
    "https://172.31.255.255/image.jpg",
    "https://192.0.0.1/image.jpg",
    "https://192.0.2.1/image.jpg",
    "https://192.168.0.1/image.jpg",
    "https://198.18.0.1/image.jpg",
    "https://198.51.100.1/image.jpg",
    "https://203.0.113.1/image.jpg",
    "https://169.254.0.1/image.jpg",
    "https://224.0.0.1/image.jpg",
    "https://255.255.255.255/image.jpg",
    "https://[::]/image.jpg",
    "https://[::1]/image.jpg",
    "https://[::ffff:127.0.0.1]/image.jpg",
    "https://[::ffff:c0a8:1]/image.jpg",
    "https://[64:ff9b::c0a8:1]/image.jpg",
    "https://[100::1]/image.jpg",
    "https://[2001:db8::1]/image.jpg",
    "https://[2002:c0a8:1::]/image.jpg",
    "https://[fc00::1]/image.jpg",
    "https://[fdff::1]/image.jpg",
    "https://[fe80::1]/image.jpg",
    "https://[ff02::1]/image.jpg",
  ])("rejects private IP literal %s", (rawUrl) => {
    const result = validateFetchUrl(rawUrl);

    expect(result).toEqual({
      ok: false,
      error: "blocked_private_address",
    });
  });

  it.each([
    "https://8.8.8.8/image.jpg",
    "https://93.184.216.34/image.jpg",
    "https://100.128.0.1/image.jpg",
    "https://172.32.0.1/image.jpg",
    "https://192.0.1.1/image.jpg",
    "https://[2001:4860:4860::8888]/image.jpg",
  ])("allows public IP literal boundary %s", (rawUrl) => {
    const result = validateFetchUrl(rawUrl);

    expect(result.ok).toBe(true);
  });

  it.each([
    "https://localhost/image.jpg",
    "https://app.localhost/image.jpg",
    "https://example.local/image.jpg",
    "https://example.internal/image.jpg",
  ])("rejects local hostnames %s", (rawUrl) => {
    const result = validateFetchUrl(rawUrl);

    expect(result).toEqual({
      ok: false,
      error: "blocked_hostname",
    });
  });

  it("rejects recursive requests to the service origin", () => {
    const result = validateFetchUrl(
      "https://media.example.com/v1/resolve?url=https%3A%2F%2Fexample.com",
      { serviceOrigin: "https://media.example.com" },
    );

    expect(result).toEqual({
      ok: false,
      error: "blocked_recursive_request",
    });
  });

  it("rejects recursive requests when the target hostname has a trailing dot", () => {
    const result = validateFetchUrl(
      "https://media.example.com./v1/resolve?url=https%3A%2F%2Fexample.com",
      { serviceOrigin: "https://media.example.com" },
    );

    expect(result).toEqual({
      ok: false,
      error: "blocked_recursive_request",
    });
  });
});

describe("validateRedirectLocation", () => {
  it("allows safe relative redirects", () => {
    const result = validateRedirectLocation(
      "/next-image.jpg#fragment",
      new URL("https://example.com/image.jpg"),
    );

    expect(result).toEqual({
      ok: true,
      url: "https://example.com/next-image.jpg",
      cacheKey: "https://example.com/next-image.jpg",
    });
  });

  it("validates Location before following redirects", () => {
    const result = validateRedirectLocation(
      "http://127.0.0.1/private",
      new URL("https://example.com/image.jpg"),
    );

    expect(result).toEqual({
      ok: false,
      error: "blocked_private_address",
    });
  });
});
