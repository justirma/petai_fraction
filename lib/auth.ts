import { betterAuth } from "better-auth";
import { drizzleAdapter } from "better-auth/adapters/drizzle";
import { organization, twoFactor } from "better-auth/plugins";
import { db } from "@/lib/db";
import * as schema from "@/lib/db/schema";
import { env } from "@/lib/env";

export const auth = betterAuth({
  database: drizzleAdapter(db, {
    provider: "pg",
    schema,
  }),

  baseURL: env.BETTER_AUTH_URL,
  secret: env.BETTER_AUTH_SECRET,

  // ── Email + password (enabled by default) ──
  emailAndPassword: {
    enabled: true,
    requireEmailVerification: false, // Set true when email service configured
  },

  // ── Social providers ──
  // Uncomment and add credentials as needed per project.
  // Each requires clientId + clientSecret in env vars.
  socialProviders: {
    // google: {
    //   clientId: env.GOOGLE_CLIENT_ID!,
    //   clientSecret: env.GOOGLE_CLIENT_SECRET!,
    // },
    // github: {
    //   clientId: env.GITHUB_CLIENT_ID!,
    //   clientSecret: env.GITHUB_CLIENT_SECRET!,
    // },
    // apple: {
    //   clientId: env.APPLE_CLIENT_ID!,
    //   clientSecret: env.APPLE_CLIENT_SECRET!,
    // },
  },

  // ── Plugins ──
  plugins: [
    organization({
      // Default roles: owner, admin, member
      // Dynamic access control: orgs can create custom roles at runtime
    }),
    twoFactor({
      issuer: "DevHawk",
    }),
    // Add per project:
    // passkey(),
    // magicLink({ sendMagicLink: async ({ email, url }) => { ... } }),
    // stripe({ stripeSecretKey: env.STRIPE_SECRET_KEY!, ... }),
    // apiKey(),
    // admin(),
  ],

  // ── Session ──
  session: {
    cookieCache: {
      enabled: true,
      maxAge: 5 * 60, // 5 minutes
    },
  },

  // ── Account linking ──
  account: {
    accountLinking: {
      enabled: true,
      trustedProviders: ["google", "apple"],
    },
  },
});

export type Session = typeof auth.$Infer.Session;
export type User = typeof auth.$Infer.Session.user;
