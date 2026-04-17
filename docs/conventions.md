# Code conventions

Read this BEFORE writing any code. These patterns are non-negotiable.

## File organization

- `app/` — Next.js App Router pages, layouts, API routes. Route groups: `(auth)` for login/signup, `(dashboard)` for authenticated pages.
- `components/ui/` — shadcn/ui primitives (Button, Card, Input). Do not modify unless the design system changes.
- `components/[feature]/` — Feature-specific components. Colocate with the feature, not in a global folder.
- `lib/` — Shared utilities. `lib/db/` for database, `lib/auth.ts` for auth, `lib/jobs/` for queues.
- `tests/` — Mirrors the source structure. `tests/unit/`, `tests/integration/`, `tests/e2e/`.

## Naming

- Files: `kebab-case.ts` for utilities, `PascalCase.tsx` for components
- Exports: named exports everywhere. Default exports only for page.tsx, layout.tsx, and route.ts (Next.js requirement).
- Database tables: `snake_case` singular (`user`, `account`, `organization`). Columns: `snake_case` (`created_at`). This matches Better Auth's default table naming.
- Zod schemas: `camelCase` matching the TypeScript interface (`createUserSchema`, `updateProductSchema`).
- BullMQ queues: `kebab-case` (`email`, `ai-agent`, `data-export`).

## TypeScript

- Strict mode enabled. No `any` types. Use `unknown` + type narrowing instead.
- Prefer `interface` for object shapes, `type` for unions and intersections.
- Infer types from Drizzle schema (`typeof user.$inferSelect`) rather than writing them manually.
- Use `satisfies` operator for type checking without widening.
- **Dual-suppression ordering** (Biome + ESLint): when a line needs both `biome-ignore` and an ESLint disable, `biome-ignore` must be the comment directly above the violation. Put the ESLint disable inline on the same line. If `eslint-disable-next-line` goes between `biome-ignore` and the code, Biome reports the suppression as unused (error).
  ```typescript
  // biome-ignore lint/suspicious/noExplicitAny: <reason>
  type Foo = any; // eslint-disable-line @typescript-eslint/no-explicit-any
  ```

## React patterns

- Server Components by default. Add `"use client"` only when the component needs hooks, event handlers, or browser APIs.
- Use `useActionState` for form submissions with Server Actions (not `useState` + `onSubmit`).
- Data fetching in Server Components via direct Drizzle queries. No `useEffect` + `fetch` for initial data.
- Client state with Zustand only when React state is insufficient (cross-component, persisted).
- Server cache with TanStack Query only for data that needs refetching, optimistic updates, or deduplication.

## API routes vs Server Actions

- **Server Actions** for mutations triggered by user interaction (form submit, button click). Always validate input with Zod.
- **API routes** for webhooks (Stripe, external services), public API endpoints, and Better Auth callbacks.
- Never use API routes for internal app mutations — use Server Actions.

## Error handling

- Server Actions: return `{ success: boolean, error?: string, data?: T }`. Never throw from a Server Action.
- API routes: return typed JSON responses with appropriate HTTP status codes.
- BullMQ jobs: let errors throw naturally. BullMQ handles retries. Log the error for observability.
- Use `error.tsx` boundary files for uncaught UI errors.

## Validation

- ALL external input goes through Zod first: form data, API request bodies, query params, webhook payloads.
- Use `drizzle-zod` to generate insert/select schemas from Drizzle tables.
- Share schemas between client (form validation) and server (Server Action validation).
- Environment variables validated at startup via `@t3-oss/env-nextjs` in `lib/env.ts`.

## UI design principles

- **Intentional aesthetics.** Every project should have a clear visual direction established during bootstrap. Execute that direction with precision — bold maximalism and refined minimalism both work. The key is consistency, not intensity.
- **Distinctive typography.** Avoid defaulting to Inter, Roboto, Arial, or system fonts. Choose a characterful display font paired with a complementary body font. Import via `next/font/google` or `next/font/local`.
- **Cohesive color system.** Use the CSS custom properties in `globals.css` `@theme` block. Dominant colors with sharp accents outperform timid, evenly-distributed palettes. Commit to a palette and use it everywhere.
- **Purposeful motion.** One well-orchestrated page load with staggered reveals creates more delight than scattered micro-interactions. Use CSS transitions for simple states, and the Motion library for complex sequences. Every animation should communicate meaning.
- **Spatial composition.** Use generous negative space OR controlled density — not the default middle ground. Consider asymmetry, overlap, and grid-breaking elements where they serve the design.
- **No generic AI aesthetics.** Avoid: purple gradients on white backgrounds, cookie-cutter card grids, predictable hero-section layouts, and any pattern that looks like "AI-generated starter template." If it looks like every other SaaS landing page, push harder.
- **shadcn/ui as foundation, not ceiling.** Use primitives from `components/ui/` as building blocks, then customize with the project's design tokens. Override defaults to match the aesthetic direction.

## Imports

- Use `@/` path alias for all imports (e.g., `import { db } from "@/lib/db"`).
- Group imports: 1) React/Next.js, 2) external packages, 3) internal modules. Blank line between groups.
- No barrel exports except for `lib/db/schema/index.ts`.
