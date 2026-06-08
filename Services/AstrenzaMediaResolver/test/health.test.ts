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
