export type UrlGuardOptions = {
  serviceOrigin?: string;
};

export type UrlGuardResult =
  | {
      ok: true;
      url: string;
      cacheKey: string;
    }
  | {
      ok: false;
      error:
        | "invalid_url"
        | "unsupported_scheme"
        | "empty_host"
        | "credentials_not_allowed"
        | "blocked_private_address"
        | "blocked_hostname"
        | "blocked_recursive_request";
    };

export function validateFetchUrl(
  raw: string,
  options: UrlGuardOptions = {},
): UrlGuardResult {
  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    return { ok: false, error: "invalid_url" };
  }

  return validateUrl(url, options);
}

export function validateRedirectLocation(
  location: string,
  baseUrl: URL,
  options: UrlGuardOptions = {},
): UrlGuardResult {
  let url: URL;
  try {
    url = new URL(location, baseUrl);
  } catch {
    return { ok: false, error: "invalid_url" };
  }

  return validateUrl(url, options);
}

function validateUrl(url: URL, options: UrlGuardOptions): UrlGuardResult {
  if (url.protocol !== "http:" && url.protocol !== "https:") {
    return { ok: false, error: "unsupported_scheme" };
  }

  if (!url.hostname) {
    return { ok: false, error: "empty_host" };
  }

  if (url.username || url.password) {
    return { ok: false, error: "credentials_not_allowed" };
  }

  const hostname = canonicalHostname(url.hostname);
  if (isBlockedHostname(hostname)) {
    return { ok: false, error: "blocked_hostname" };
  }

  if (isBlockedIpLiteral(hostname)) {
    return { ok: false, error: "blocked_private_address" };
  }

  if (isRecursiveServiceRequest(url, options.serviceOrigin)) {
    return { ok: false, error: "blocked_recursive_request" };
  }

  url.hash = "";
  const normalized = url.href;
  return {
    ok: true,
    url: normalized,
    cacheKey: normalized,
  };
}

type OriginParts = {
  protocol: string;
  hostname: string;
  port: string;
};

function isRecursiveServiceRequest(
  url: URL,
  rawServiceOrigin: string | undefined,
): boolean {
  const serviceOrigin = originParts(rawServiceOrigin);
  if (!serviceOrigin) return false;

  return originsMatch(originParts(url), serviceOrigin);
}

function originParts(value: URL): OriginParts;
function originParts(value: string | undefined): OriginParts | null;
function originParts(value: URL | string | undefined): OriginParts | null {
  if (!value) return null;

  try {
    const url = value instanceof URL ? value : new URL(value);
    return {
      protocol: url.protocol,
      hostname: canonicalHostname(url.hostname),
      port: normalizedPort(url.protocol, url.port),
    };
  } catch {
    return null;
  }
}

function originsMatch(left: OriginParts | null, right: OriginParts): boolean {
  return (
    left !== null &&
    left.protocol === right.protocol &&
    left.hostname === right.hostname &&
    left.port === right.port
  );
}

function normalizedPort(protocol: string, port: string): string {
  if (port) return port;
  if (protocol === "http:") return "80";
  if (protocol === "https:") return "443";
  return "";
}

function canonicalHostname(hostname: string): string {
  return stripIpv6Brackets(hostname).toLowerCase().replace(/\.+$/, "");
}

function stripIpv6Brackets(hostname: string): string {
  if (hostname.startsWith("[") && hostname.endsWith("]")) {
    return hostname.slice(1, -1);
  }
  return hostname;
}

function isBlockedHostname(hostname: string): boolean {
  return (
    hostname === "localhost" ||
    hostname.endsWith(".localhost") ||
    hostname.endsWith(".local") ||
    hostname.endsWith(".internal")
  );
}

function isBlockedIpLiteral(hostname: string): boolean {
  const ipv4 = parseIpv4(hostname);
  if (ipv4) return isBlockedIpv4(ipv4);

  const ipv6 = parseIpv6(hostname);
  if (ipv6) return isBlockedIpv6(ipv6);

  return false;
}

function parseIpv4(hostname: string): number[] | null {
  if (!/^\d{1,3}(?:\.\d{1,3}){3}$/.test(hostname)) return null;

  const octets = hostname.split(".").map(Number);
  if (octets.some((octet) => octet > 255)) return null;
  return octets;
}

function isBlockedIpv4([first, second, third]: number[]): boolean {
  return (
    first === 0 ||
    first === 10 ||
    (first === 100 && second >= 64 && second <= 127) ||
    first === 127 ||
    (first === 169 && second === 254) ||
    (first === 172 && second >= 16 && second <= 31) ||
    (first === 192 && second === 0 && third === 0) ||
    (first === 192 && second === 0 && third === 2) ||
    (first === 192 && second === 88 && third === 99) ||
    (first === 192 && second === 168) ||
    (first === 198 && (second === 18 || second === 19)) ||
    (first === 198 && second === 51 && third === 100) ||
    (first === 203 && second === 0 && third === 113) ||
    first >= 224
  );
}

function parseIpv6(hostname: string): number[] | null {
  if (!hostname.includes(":")) return null;
  if (hostname.includes(".")) return null;

  const sections = hostname.split("::");
  if (sections.length > 2) return null;

  const head = parseIpv6Section(sections[0] ?? "");
  const tail = parseIpv6Section(sections[1] ?? "");
  if (!head || !tail) return null;

  if (sections.length === 1) {
    return head.length === 8 ? head : null;
  }

  const zeroCount = 8 - head.length - tail.length;
  if (zeroCount < 1) return null;

  return [...head, ...Array<number>(zeroCount).fill(0), ...tail];
}

function parseIpv6Section(section: string): number[] | null {
  if (!section) return [];

  return section.split(":").map((part) => {
    if (!/^[0-9a-f]{1,4}$/i.test(part)) return Number.NaN;
    return Number.parseInt(part, 16);
  });
}

function isBlockedIpv6(hextets: number[]): boolean {
  if (hextets.some(Number.isNaN)) return false;

  if (hextets.every((hextet) => hextet === 0)) {
    return true;
  }

  if (hextets.slice(0, 7).every((hextet) => hextet === 0) && hextets[7] === 1) {
    return true;
  }

  const embeddedIpv4 = embeddedIpv4FromIpv6(hextets);
  if (embeddedIpv4 && isBlockedIpv4(embeddedIpv4)) {
    return true;
  }

  const first = hextets[0] ?? 0;
  const second = hextets[1] ?? 0;
  return (
    (first & 0xfe00) === 0xfc00 ||
    (first & 0xffc0) === 0xfe80 ||
    (first & 0xff00) === 0xff00 ||
    (first === 0x0064 && second === 0xff9b && hextets[2] === 0x0001) ||
    (first === 0x0100 &&
      hextets[1] === 0 &&
      hextets[2] === 0 &&
      hextets[3] === 0) ||
    (first === 0x2001 && (second === 0x0000 || second === 0x0db8)) ||
    first === 0x2002
  );
}

function embeddedIpv4FromIpv6(hextets: number[]): number[] | null {
  if (
    hextets.slice(0, 5).every((hextet) => hextet === 0) &&
    hextets[5] === 0xffff
  ) {
    return hextetsToIpv4(hextets[6] ?? 0, hextets[7] ?? 0);
  }

  if (hextets.slice(0, 6).every((hextet) => hextet === 0)) {
    return hextetsToIpv4(hextets[6] ?? 0, hextets[7] ?? 0);
  }

  if (
    hextets[0] === 0x0064 &&
    hextets[1] === 0xff9b &&
    hextets.slice(2, 6).every((hextet) => hextet === 0)
  ) {
    return hextetsToIpv4(hextets[6] ?? 0, hextets[7] ?? 0);
  }

  return null;
}

function hextetsToIpv4(high: number, low: number): number[] {
  return [high >> 8, high & 0xff, low >> 8, low & 0xff];
}

// Cloudflare Worker core から DNS 解決後の private IP は見えない。
// self-host adapter では fetch 前に DNS lookup guard を追加する。
