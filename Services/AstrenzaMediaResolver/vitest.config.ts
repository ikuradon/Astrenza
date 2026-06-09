import { defineWorkersConfig } from "@cloudflare/vitest-pool-workers/config";
import { defineConfig } from "vitest/config";

const usesWorkersPool = process.env.npm_lifecycle_event === "cf:test";

export default usesWorkersPool
  ? defineWorkersConfig({
      test: {
        pool: "@cloudflare/vitest-pool-workers",
        poolOptions: {
          workers: {
            main: "./src/index.ts",
            wrangler: {
              configPath: "./wrangler.jsonc",
            },
          },
        },
      },
    })
  : defineConfig({});
