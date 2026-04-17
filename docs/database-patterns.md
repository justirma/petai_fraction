# Database patterns

## Schema definition

Define tables in `lib/db/schema/`. One file per domain (auth.ts, product.ts, order.ts). Export everything from `lib/db/schema/index.ts`.

```typescript
import { pgTable, text, timestamp, integer, boolean, uuid } from "drizzle-orm/pg-core";
import { user, organization } from "./auth";

export const product = pgTable("product", {
  id: uuid("id").defaultRandom().primaryKey(),
  name: text("name").notNull(),
  price: integer("price").notNull(), // Store in cents
  active: boolean("active").notNull().default(true),
  organizationId: text("organization_id")
    .notNull()
    .references(() => organization.id, { onDelete: "cascade" }),
  createdBy: text("created_by")
    .notNull()
    .references(() => user.id),
  createdAt: timestamp("created_at").notNull().defaultNow(),
  updatedAt: timestamp("updated_at").notNull().defaultNow(),
});
```

## Validation schemas

Generate Zod schemas from Drizzle tables for type-safe validation:

```typescript
import { createInsertSchema, createSelectSchema } from "drizzle-zod";
import { product } from "@/lib/db/schema";

export const insertProductSchema = createInsertSchema(product, {
  name: (schema) => schema.min(1).max(200),
  price: (schema) => schema.min(0),
});

export const selectProductSchema = createSelectSchema(product);

export type NewProduct = typeof insertProductSchema._output;
export type Product = typeof selectProductSchema._output;
```

## Queries

Use Drizzle's query builder. It mirrors SQL — what you write is what executes.

```typescript
// Simple select
const found = await db.query.product.findFirst({
  where: eq(product.id, productId),
});

// With relations
const productWithCreator = await db.query.product.findFirst({
  where: eq(product.id, productId),
  with: { createdBy: true },
});

// Filtered list with pagination
const items = await db
  .select()
  .from(product)
  .where(and(
    eq(product.organizationId, orgId),
    eq(product.active, true),
  ))
  .orderBy(desc(product.createdAt))
  .limit(20)
  .offset(page * 20);
```

## Migrations

**Drizzle is the single source of truth for all database schema**, including Better Auth tables. Never use `npx auth@latest migrate` or Better Auth's CLI for migrations — it uses a separate Kysely-based migration system that will conflict with Drizzle migrations (duplicate table creation, column mismatches).

The auth schema in `lib/db/schema/auth.ts` is manually maintained to match what Better Auth expects. When adding Better Auth plugins, update the Drizzle schema to include any new tables or columns the plugin requires, then generate a Drizzle migration.

1. Edit schema files in `lib/db/schema/`
2. Run `pnpm db:generate` — creates SQL migration in `lib/db/migrations/`
3. Review the generated SQL
4. Run `pnpm db:migrate` locally to test
5. Commit both schema changes and migration files
6. On deploy, the pre-deploy Job runs `drizzle-kit migrate` automatically

### Destructive changes (expand/contract)

Never drop or rename a column in a single deploy. Use three deploys:

1. **Expand**: Add new column (nullable), deploy code that writes to both columns
2. **Migrate**: Backfill new column from old data, verify integrity
3. **Contract**: Deploy code using only new column, then drop old column

## Multi-tenancy with organizations

All tenant-scoped tables include `organization_id`. Every query MUST filter by the current user's active organization:

```typescript
// In a Server Component or Server Action
const session = await auth.api.getSession({ headers: await headers() });
const orgId = session?.session?.activeOrganizationId;
if (!orgId) throw new Error("No active organization");

const items = await db.select().from(product)
  .where(eq(product.organizationId, orgId));
```

## Row-Level Security (when needed)

Drizzle supports native RLS for defense-in-depth:

```typescript
import { pgTable, pgPolicy, pgRole } from "drizzle-orm/pg-core";

export const tenantRole = pgRole("tenant_role");

export const product = pgTable("product", { ... }, (table) => [
  pgPolicy("tenant_isolation", {
    for: "all",
    to: tenantRole,
    using: sql`organization_id = current_setting('app.org_id')`,
  }),
]);
```
