# Testing patterns

## Test structure

```
tests/
├── unit/           # Pure function tests, no I/O
├── integration/    # Tests with database, Redis, or external calls
└── e2e/            # Playwright browser tests
```

## Vitest — unit tests

Test pure logic, validators, and utilities:

```typescript
// tests/unit/validators.test.ts
import { describe, it, expect } from "vitest";
import { insertProductSchema } from "@/lib/db/schema/product";

describe("insertProductSchema", () => {
  it("accepts valid product data", () => {
    const result = insertProductSchema.safeParse({
      name: "Widget",
      price: 1999,
      organizationId: "org_123",
      createdBy: "user_456",
    });
    expect(result.success).toBe(true);
  });

  it("rejects negative prices", () => {
    const result = insertProductSchema.safeParse({
      name: "Widget",
      price: -1,
      organizationId: "org_123",
      createdBy: "user_456",
    });
    expect(result.success).toBe(false);
  });
});
```

## Vitest — integration tests

Test database interactions. CI workflow provides PG + Redis services:

```typescript
// tests/integration/product.test.ts
import { describe, it, expect, beforeEach } from "vitest";
import { db } from "@/lib/db";
import { product } from "@/lib/db/schema";
import { eq } from "drizzle-orm";

beforeEach(async () => {
  await db.delete(product); // Clean state
});

it("creates and retrieves a product", async () => {
  const [created] = await db.insert(product).values({
    name: "Test Widget",
    price: 999,
    organizationId: "org_test",
    createdBy: "user_test",
  }).returning();

  const found = await db.query.product.findFirst({
    where: eq(product.id, created.id),
  });

  expect(found?.name).toBe("Test Widget");
  expect(found?.price).toBe(999);
});
```

## Playwright — E2E tests

Test user flows in a real browser:

```typescript
// tests/e2e/auth.spec.ts
import { test, expect } from "@playwright/test";

test("user can sign up and reach dashboard", async ({ page }) => {
  await page.goto("/sign-up");
  await page.fill('[name="name"]', "Test User");
  await page.fill('[name="email"]', "test@example.com");
  await page.fill('[name="password"]', "securepassword123");
  await page.click('button[type="submit"]');
  await expect(page).toHaveURL("/dashboard");
  await expect(page.locator("h1")).toContainText("Dashboard");
});
```

## Running tests

```bash
pnpm test              # Vitest watch mode (unit + integration)
pnpm test:run          # Vitest single run (CI)
pnpm test:e2e          # Playwright headless
pnpm test:e2e:ui       # Playwright with interactive UI
```

## Test naming convention

- File: `[module].test.ts` for unit/integration, `[flow].spec.ts` for E2E
- Describe: module or feature name
- It: plain English description starting with a verb ("creates", "rejects", "redirects")

## What to test

- **Always test:** Zod schemas, database queries, Server Action return values, auth guards, BullMQ job processors
- **E2E test:** Critical user paths (signup, login, core workflow, payment)
- **Don't test:** shadcn/ui component internals, Next.js framework behavior, third-party library correctness
