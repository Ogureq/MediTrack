import { defineConfig } from "vitest/config";

// Pure-logic unit tests only: no network, no real KV, no Wrangler runtime.
// Everything under test (quota arithmetic, JWT issue/verify, request-schema
// validation, SSE-event mapping) is plain TypeScript that happens to run
// inside a Worker in production but has no Worker-specific dependency, so a
// plain Node environment is sufficient and keeps the test run fast.
export default defineConfig({
  test: {
    include: ["test/**/*.test.ts"],
    environment: "node"
  }
});
