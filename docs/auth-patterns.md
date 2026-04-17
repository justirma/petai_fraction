# Auth patterns

## Configuration

Auth is configured in `lib/auth.ts` (server) and `lib/auth-client.ts` (client). The route handler at `app/api/auth/[...all]/route.ts` handles all auth API calls.

**Important:** The Drizzle schema in `lib/db/schema/auth.ts` is passed directly to the Better Auth adapter via the `schema` option. Table names use singular form (`user`, `session`, `account`) matching Better Auth defaults. Never run `npx auth@latest migrate` — use Drizzle migrations exclusively. See @docs/database-patterns.md for details.

## Getting the session

### Server Components
```typescript
import { auth } from "@/lib/auth";
import { headers } from "next/headers";

export default async function DashboardPage() {
  const session = await auth.api.getSession({ headers: await headers() });
  if (!session) redirect("/sign-in");
  return <div>Welcome, {session.user.name}</div>;
}
```

### Client Components
```typescript
"use client";
import { useSession } from "@/lib/auth-client";

export function UserGreeting() {
  const { data: session, isPending } = useSession();
  if (isPending) return <Skeleton />;
  if (!session) return null;
  return <span>{session.user.name}</span>;
}
```

### Server Actions
```typescript
"use server";
import { auth } from "@/lib/auth";
import { headers } from "next/headers";

export async function createProduct(data: FormData) {
  const session = await auth.api.getSession({ headers: await headers() });
  if (!session) return { success: false, error: "Unauthorized" };
  // ... proceed with session.user and session.session.activeOrganizationId
}
```

## Social login

Add providers in `lib/auth.ts` under `socialProviders`. Each needs env vars:

```typescript
socialProviders: {
  google: {
    clientId: env.GOOGLE_CLIENT_ID!,
    clientSecret: env.GOOGLE_CLIENT_SECRET!,
  },
},
```

Client-side sign-in:
```typescript
import { signIn } from "@/lib/auth-client";
await signIn.social({ provider: "google", callbackURL: "/dashboard" });
```

## Organizations (multi-tenancy)

The organization plugin is pre-configured. Use the client helpers:

```typescript
import { useActiveOrganization, useListOrganizations } from "@/lib/auth-client";

// Get current org
const { data: activeOrg } = useActiveOrganization();

// List user's orgs
const { data: orgs } = useListOrganizations();

// Create org
await authClient.organization.create({ name: "Acme Corp", slug: "acme" });

// Invite member
await authClient.organization.inviteMember({
  email: "colleague@example.com",
  role: "admin",
});

// Switch active org
await authClient.organization.setActive({ organizationId: "org_123" });
```

## Adding plugins

Add server plugin in `lib/auth.ts`, client plugin in `lib/auth-client.ts`:

```typescript
// Server: lib/auth.ts
import { passkey } from "better-auth/plugins";
plugins: [organization(), twoFactor(), passkey()],

// Client: lib/auth-client.ts
import { passkeyClient } from "better-auth/client/plugins";
plugins: [organizationClient(), twoFactorClient(), passkeyClient()],
```

## Protecting routes

Use Next.js middleware for route protection:

```typescript
// middleware.ts
import { auth } from "@/lib/auth";
import { headers } from "next/headers";
import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";

export async function middleware(request: NextRequest) {
  const session = await auth.api.getSession({ headers: request.headers });
  if (!session && request.nextUrl.pathname.startsWith("/dashboard")) {
    return NextResponse.redirect(new URL("/sign-in", request.url));
  }
  return NextResponse.next();
}

export const config = { matcher: ["/dashboard/:path*"] };
```

## Superadmin bootstrap

After a fresh deploy, the first user who signs up has no org membership and sees "No organization". The seed includes `POST /api/bootstrap` — a one-time, token-gated endpoint that creates a default org and makes a user the owner. See `docs/deployment.md` → "First deploy" step 11 for the curl.

The endpoint self-disables after first use (409 once any org owner exists). `SUPERADMIN_SETUP_TOKEN` env var must be set in DO dashboard.

## Common gotchas

### Role-based self-join must include the default role

If your project has role-based access gating (e.g. a `SELF_JOIN_ROLES` map that controls which user roles can access each area), make sure the **default user role** is included for at least the primary area. Better Auth's user schema defaults new accounts to whatever `role` default your schema declares. If the self-join map only lists elevated roles (`admin`, `manager`), no one can access anything after sign-up.

Check: what role does a brand-new user get? Is that role in the self-join allowlist for the main app area?
