import { defineConfig } from "drizzle-kit";
import { readFileSync } from "fs";
import { resolve } from "path";

// Load DATABASE_URL from .env.local directly.
// We avoid importing lib/env here because drizzle-kit runs outside Next.js
// and the full env validation would fail without all vars set.
function loadDatabaseUrl(): string {
  // Check process.env first (CI, production, or manually sourced)
  if (process.env.DATABASE_URL) return process.env.DATABASE_URL;

  // Fall back to .env.local
  try {
    const content = readFileSync(resolve(process.cwd(), ".env.local"), "utf-8");
    for (const line of content.split("\n")) {
      const trimmed = line.trim();
      if (trimmed.startsWith("DATABASE_URL=")) {
        let val = trimmed.slice("DATABASE_URL=".length).trim();
        if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) {
          val = val.slice(1, -1);
        }
        return val;
      }
    }
  } catch {
    // .env.local doesn't exist
  }

  throw new Error("DATABASE_URL not found. Set it in .env.local or as an environment variable.");
}

export default defineConfig({
  dialect: "postgresql",
  schema: "./lib/db/schema/index.ts",
  out: "./lib/db/migrations",
  dbCredentials: {
    url: loadDatabaseUrl(),
  },
  verbose: true,
  strict: true,
});
