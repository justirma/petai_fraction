import { describe, it, expect } from "vitest";

describe("seed project", () => {
  it("validates env schema exists", async () => {
    const { env } = await import("@/lib/env");
    // In test env, SKIP_ENV_VALIDATION may be set
    expect(env).toBeDefined();
  });
});
