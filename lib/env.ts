import { createEnv } from "@t3-oss/env-nextjs";
import { z } from "zod";

export const env = createEnv({
  // ── Server-side env vars (never exposed to client) ──
  server: {
    // Database
    DATABASE_URL: z.string().url(),

    // Redis (BullMQ + cache)
    REDIS_URL: z.string().url(),

    // Better Auth
    BETTER_AUTH_SECRET: z.string().min(32),
    BETTER_AUTH_URL: z.string().url(),

    // AI providers (at least one required)
    ANTHROPIC_API_KEY: z.string().optional(),
    OPENAI_API_KEY: z.string().optional(),

    // Stripe
    STRIPE_SECRET_KEY: z.string().optional(),
    STRIPE_WEBHOOK_SECRET: z.string().optional(),

    // Resend
    RESEND_API_KEY: z.string().optional(),

    // Superadmin bootstrap (one-time setup, see POST /api/bootstrap)
    SUPERADMIN_SETUP_TOKEN: z.string().optional(),

    // Node environment
    NODE_ENV: z.enum(["development", "production", "test"]).default("development"),
  },

  // ── Client-side env vars (NEXT_PUBLIC_ prefix) ──
  client: {
    NEXT_PUBLIC_APP_URL: z.string().url(),
  },

  // ── Runtime values (populated from process.env) ──
  runtimeEnv: {
    DATABASE_URL: process.env.DATABASE_URL,
    REDIS_URL: process.env.REDIS_URL,
    BETTER_AUTH_SECRET: process.env.BETTER_AUTH_SECRET,
    BETTER_AUTH_URL: process.env.BETTER_AUTH_URL,
    ANTHROPIC_API_KEY: process.env.ANTHROPIC_API_KEY,
    OPENAI_API_KEY: process.env.OPENAI_API_KEY,
    STRIPE_SECRET_KEY: process.env.STRIPE_SECRET_KEY,
    STRIPE_WEBHOOK_SECRET: process.env.STRIPE_WEBHOOK_SECRET,
    RESEND_API_KEY: process.env.RESEND_API_KEY,
    SUPERADMIN_SETUP_TOKEN: process.env.SUPERADMIN_SETUP_TOKEN,
    NODE_ENV: process.env.NODE_ENV,
    NEXT_PUBLIC_APP_URL: process.env.NEXT_PUBLIC_APP_URL,
  },

  // Skip validation during Docker builds
  skipValidation: !!process.env.SKIP_ENV_VALIDATION,
  emptyStringAsUndefined: true,
});
