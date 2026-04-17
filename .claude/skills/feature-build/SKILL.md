---
name: feature-build
description: >
  Guides implementation of a feature or user story on a DevHawk project.
  Use when building a specific feature, implementing a story from the backlog,
  or adding new functionality. Triggers on phrases like "build [feature]",
  "implement [story]", "add [capability]", "work on E2-S3", or any request
  to implement application functionality. Ensures code follows stack conventions
  and includes tests.
---

# Feature Build Guide

You are implementing a feature on a DevHawk stack project. Before writing any code:

1. Read `@docs/conventions.md` (if not already loaded)
2. Identify which reference docs are relevant to this feature
3. Plan the implementation, then execute

## Implementation checklist

For every feature, work through these in order:

### 1. Schema (if new data)
- [ ] Define table in `lib/db/schema/[domain].ts`
- [ ] Include `organizationId` if tenant-scoped
- [ ] Export from `lib/db/schema/index.ts`
- [ ] Create Zod validation schemas with `drizzle-zod`
- [ ] Run `pnpm db:generate` to create migration
- [ ] Review generated SQL migration file
- [ ] Run `pnpm db:migrate` to apply locally
- Reference: @docs/database-patterns.md

### 2. Server logic
- [ ] Server Actions for user-triggered mutations
- [ ] Return `{ success, error?, data? }` — never throw
- [ ] Validate ALL input with Zod schemas
- [ ] Check session and organizationId before any data access
- [ ] API routes only for webhooks or external consumers
- Reference: @docs/conventions.md

### 3. Background jobs (if async work)
- [ ] Add queue in `lib/jobs/queues.ts`
- [ ] Create processor in `lib/jobs/processors/`
- [ ] Register worker in `lib/jobs/worker.ts`
- [ ] Enqueue from Server Action or API route
- Reference: @docs/background-jobs.md

### 4. UI
- [ ] Server Component by default (data fetching happens here)
- [ ] Client Component only when hooks or event handlers needed
- [ ] Use shadcn/ui primitives from `components/ui/` as foundation
- [ ] Match the project's established aesthetic direction (check `globals.css` theme and existing pages for the design language)
- [ ] Forms use `useActionState` + Server Action
- [ ] Show loading states with Suspense boundaries
- [ ] Add purposeful transitions for state changes (avoid gratuitous animation)
- Use the `frontend-design` skill for pages or components that are user-facing and visually significant
- Reference: @docs/conventions.md (UI design principles section)

### 5. Auth (if role-based or protected)
- [ ] Session check in Server Component or Server Action
- [ ] Organization check for tenant-scoped features
- [ ] Middleware route protection if entire route group is protected
- Reference: @docs/auth-patterns.md

### 6. Tests
- [ ] Unit test for Zod schemas and pure logic
- [ ] Integration test for database queries and Server Actions
- [ ] E2E test for the critical user path through this feature
- [ ] Run `pnpm test:run` to verify all pass
- Reference: @docs/testing-patterns.md

### 7. Verify
- [ ] `pnpm typecheck` passes
- [ ] `pnpm lint` passes
- [ ] `pnpm test:run` passes
- [ ] Feature works in browser (`pnpm dev`)
- [ ] Run `/code-review` against the feature diff and address any high-confidence findings before committing

## Common patterns

### Adding a CRUD feature
1. Schema → migration → Zod schemas
2. Server Actions: create, update, delete (each validates input, checks auth)
3. Server Component: list page with data fetching
4. Client Component: form with `useActionState`
5. Tests: schema validation, CRUD operations, E2E flow

### Adding an AI feature
1. Define tools with Zod parameter schemas in `lib/ai/`
2. Create chat route handler or Server Action
3. For long-running: enqueue via BullMQ, show progress
4. Client: `useChat()` hook or custom streaming UI
5. Reference: @docs/ai-patterns.md

### Adding a webhook handler
1. API route in `app/api/webhooks/[service]/route.ts`
2. Verify webhook signature (Stripe: `stripe.webhooks.constructEvent`)
3. Enqueue processing via BullMQ (don't do heavy work in the handler)
4. Return 200 immediately
5. BullMQ processor handles the actual work with retries
