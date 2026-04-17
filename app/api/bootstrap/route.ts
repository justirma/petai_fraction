import { randomUUID } from "node:crypto";
import { db } from "@/lib/db";
import { member, organization, user } from "@/lib/db/schema/auth";
import { eq } from "drizzle-orm";
import { NextResponse } from "next/server";

/**
 * POST /api/bootstrap — One-time superadmin bootstrap endpoint.
 *
 * After a fresh deploy, the first user who signs up has no org membership
 * and lands on "No organization". This endpoint solves the chicken-and-egg:
 * it creates a default org and makes an existing user the owner.
 *
 * Token-gated via SUPERADMIN_SETUP_TOKEN env var. Self-disabling: returns
 * 409 once any org with an "owner" member exists.
 *
 * Usage (after the user has signed up via /sign-up):
 *   curl -X POST https://your-app.com/api/bootstrap \
 *     -H "Content-Type: application/json" \
 *     -d '{"email":"admin@example.com","orgName":"My Company","orgSlug":"my-company"}'
 *
 * The SUPERADMIN_SETUP_TOKEN is passed via the Authorization header:
 *   -H "Authorization: Bearer <token>"
 *
 * After success, the user can sign in and they'll have org access.
 */
export async function POST(request: Request) {
  // 1. Validate token
  const token = process.env.SUPERADMIN_SETUP_TOKEN;
  if (!token) {
    return NextResponse.json(
      { error: "SUPERADMIN_SETUP_TOKEN not configured" },
      { status: 503 },
    );
  }

  const authHeader = request.headers.get("authorization");
  const bearerToken = authHeader?.startsWith("Bearer ")
    ? authHeader.slice(7)
    : null;

  if (!bearerToken || bearerToken !== token) {
    return NextResponse.json({ error: "Invalid token" }, { status: 401 });
  }

  // 2. Self-disable: if any org owner exists, bootstrap is done
  const existingOwner = await db
    .select({ id: member.id })
    .from(member)
    .where(eq(member.role, "owner"))
    .limit(1);

  if (existingOwner.length > 0) {
    return NextResponse.json(
      { error: "Already bootstrapped — an org owner exists" },
      { status: 409 },
    );
  }

  // 3. Parse request
  const body = (await request.json()) as {
    email?: string;
    orgName?: string;
    orgSlug?: string;
  };

  if (!body.email) {
    return NextResponse.json(
      { error: "email is required" },
      { status: 400 },
    );
  }

  // 4. Find the user (they must have signed up first)
  const existingUser = await db
    .select({ id: user.id, name: user.name })
    .from(user)
    .where(eq(user.email, body.email))
    .limit(1);

  if (existingUser.length === 0) {
    return NextResponse.json(
      {
        error: `No user found with email ${body.email}. They must sign up first via /sign-up, then re-run this endpoint.`,
      },
      { status: 404 },
    );
  }

  const targetUser = existingUser[0];

  // 5. Create the default organization
  const orgId = randomUUID();
  const orgName = body.orgName || "Default Organization";
  const orgSlug = body.orgSlug || "default";

  await db.insert(organization).values({
    id: orgId,
    name: orgName,
    slug: orgSlug,
  });

  // 6. Add the user as owner
  await db.insert(member).values({
    id: randomUUID(),
    organizationId: orgId,
    userId: targetUser.id,
    role: "owner",
  });

  return NextResponse.json({
    success: true,
    message: `${targetUser.name} is now owner of "${orgName}"`,
    organizationId: orgId,
    userId: targetUser.id,
  });
}
