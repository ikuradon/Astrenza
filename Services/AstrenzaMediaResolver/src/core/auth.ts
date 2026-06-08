const encoder = new TextEncoder();

type TimingSafeSubtleCrypto = SubtleCrypto & {
  timingSafeEqual(left: ArrayBuffer, right: ArrayBuffer): boolean;
};

export function bearerToken(request: Request): string | null {
  const header = request.headers.get("Authorization");
  const match = header?.match(/^Bearer\s+(.+)$/i);
  if (!match) return null;
  const token = match[1]?.trim() ?? "";
  return token.length > 0 ? token : null;
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

  return (crypto.subtle as TimingSafeSubtleCrypto).timingSafeEqual(
    providedHash,
    expectedHash,
  );
}
