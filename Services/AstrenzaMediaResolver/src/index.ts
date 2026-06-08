import { bearerToken, verifyBearerToken } from "./core/auth";
import { validateFetchUrl } from "./core/url-guard";

type ResolverEnv = Env & {
  ASTRENZA_SERVICE_TOKEN?: string;
};

export default {
  async fetch(
    request: Request,
    env: ResolverEnv,
    _ctx: ExecutionContext,
  ): Promise<Response> {
    const url = new URL(request.url);
    if (request.method === "GET" && url.pathname === "/health") {
      return Response.json({
        ok: true,
        service: "astrenza-media-resolver",
        version: env.SERVICE_VERSION,
      });
    }

    if (request.method === "POST" && url.pathname === "/v1/resolve") {
      return handleResolve(request, env);
    }

    return Response.json({ error: "not_found" }, { status: 404 });
  },
} satisfies ExportedHandler<ResolverEnv>;

async function handleResolve(
  request: Request,
  env: ResolverEnv,
): Promise<Response> {
  if (!bearerToken(request)) {
    return jsonError("missing_authorization", 401);
  }

  if (!env.ASTRENZA_SERVICE_TOKEN) {
    return jsonError("service_token_not_configured", 500);
  }

  if (!(await verifyBearerToken(request, env.ASTRENZA_SERVICE_TOKEN))) {
    return jsonError("invalid_authorization", 403);
  }

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return jsonError("invalid_json", 400);
  }

  if (!isResolveRequestBody(body)) {
    return jsonError("invalid_request", 400);
  }

  const guard = validateFetchUrl(body.url, {
    serviceOrigin: new URL(request.url).origin,
  });
  if (!guard.ok) {
    return jsonError(guard.error, 400);
  }

  return jsonError("not_implemented", 501);
}

function isResolveRequestBody(body: unknown): body is { url: string } {
  return (
    typeof body === "object" &&
    body !== null &&
    typeof (body as { url?: unknown }).url === "string"
  );
}

function jsonError(error: string, status: number): Response {
  return Response.json({ error }, { status });
}
