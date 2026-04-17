---
name: migrate
description: >
  Analyze an existing codebase and create a phased migration plan to the DevHawk
  reference stack (Next.js 16, Drizzle, Better Auth, BullMQ, shadcn/ui, DO App Platform).
  Inspects the current tech stack, maps components to DevHawk equivalents, identifies
  risks and blockers, and produces an ordered migration backlog. Triggers on phrases like
  "migrate this app", "move to devhawk", "migration plan", "convert this codebase",
  "port this to our stack", "assess this project for migration", or any request to
  bring an existing application onto the DevHawk stack.
---

# DevHawk Migration Planner

You are analyzing an existing codebase to produce a migration plan to the DevHawk Reference Stack. The target stack is already decided — do NOT debate technology choices. Focus on understanding what exists and mapping the most efficient path to the target.

Read the DevHawk reference docs before starting:
- @docs/architecture.md — target stack and component model
- @docs/conventions.md — code patterns and naming
- @docs/database-patterns.md — Drizzle schema, queries, multi-tenancy
- @docs/auth-patterns.md — Better Auth setup
- @docs/background-jobs.md — BullMQ patterns
- @docs/deployment.md — Docker, DO App Platform

## Phase 1: Codebase inspection

Systematically analyze the existing project. Use the Explore agent or read files directly to understand each layer. Build a complete inventory:

### Framework and rendering
- What framework? (React, Vue, Angular, plain Express, etc.)
- Client-side or server-side rendering? SPA? SSR? SSG?
- Router type? (file-based, code-based, hash router)
- How are pages structured? Route organization?

### Data layer
- ORM or query approach? (Prisma, TypeORM, Sequelize, Knex, raw SQL, Mongoose)
- Database engine? (PostgreSQL, MySQL, SQLite, MongoDB, Firebase)
- Schema location and format? Migration files?
- How many tables/collections? Key relationships?
- Is there multi-tenancy? How is it implemented?

### Authentication and authorization
- Auth provider? (NextAuth/Auth.js, Passport, Firebase Auth, Clerk, Auth0, Supabase Auth, custom)
- Social login providers?
- Session strategy? (JWT, database sessions, cookies)
- Role/permission model?
- Organization/team support?

### State management and data fetching
- Client state? (Redux, Zustand, MobX, Context, Recoil, Jotai)
- Server state / data fetching? (React Query, SWR, RTK Query, tRPC, REST, GraphQL)
- Real-time? (WebSockets, SSE, Supabase realtime, Pusher)

### Background processing
- Job queues? (Bull, BullMQ, Celery, Sidekiq, none)
- Cron jobs? How are they run?
- Long-running tasks?

### UI layer
- Component library? (MUI, Ant Design, Chakra, Mantine, shadcn/ui, custom)
- CSS approach? (CSS Modules, styled-components, Tailwind, Sass, vanilla CSS)
- Design tokens / theme system?

### AI / ML
- Any AI integrations? Which providers/SDKs?
- Structured outputs, tool calling, streaming?

### External services
- Payment processor? (Stripe, PayPal, etc.)
- Email provider? (SendGrid, Postmark, SES, Resend)
- File storage? (S3, Cloudflare R2, local)
- Other third-party APIs?

### Infrastructure
- Current hosting? (Vercel, AWS, Heroku, Railway, Fly.io, self-hosted)
- CI/CD pipeline?
- Docker setup?
- Environment variable management?

### Testing
- Test framework? (Jest, Vitest, Mocha, Cypress, Playwright)
- Test coverage and patterns?
- E2E tests?

### Codebase health
- TypeScript or JavaScript? Strict mode?
- Linting / formatting setup?
- Monorepo or single package?
- Package manager? (npm, yarn, pnpm)
- Approximate size? (files, lines of code)

## Phase 2: Checkpoint — present the assessment

After inspection, present findings to the user in this format:

> ### Migration Assessment: [Project Name]
>
> **Current stack:**
> | Layer | Current | Target (DevHawk) | Migration complexity |
> |-------|---------|-------------------|---------------------|
> | Framework | [e.g. React + Vite SPA] | Next.js 16 App Router | High — requires SSR rethink |
> | Database | [e.g. Prisma + PostgreSQL] | Drizzle + PostgreSQL | Medium — schema portable, ORM swap |
> | Auth | [e.g. NextAuth v4] | Better Auth | Medium — session migration needed |
> | UI | [e.g. MUI + CSS Modules] | shadcn/ui + Tailwind v4 | High — full component rewrite |
> | State | [e.g. Redux + RTK Query] | Zustand + TanStack Query | Medium — patterns differ |
> | Jobs | [e.g. none] | BullMQ | Low — greenfield addition |
> | Hosting | [e.g. Vercel] | DO App Platform | Medium — different deploy model |
>
> **Data migration:**
> - [X tables/collections to convert]
> - [Key schema differences or normalization needed]
> - [Multi-tenancy changes if applicable]
>
> **High-risk areas:**
> - [Things that could break or require significant rework]
>
> **What can be preserved:**
> - [Business logic, API contracts, database data, etc. that transfer cleanly]
>
> **Estimated phases:** [N phases over approximately N weeks]

**STOP and wait for user confirmation before proceeding to Phase 3.** Ask if the assessment looks accurate and if there are priorities or constraints to factor in (e.g., "auth must migrate first because the current provider is being sunset").

## Phase 3: Migration plan

Create a phased migration plan. Each phase should leave the application in a working state. Never plan a "big bang" cutover.

### Ordering principles

1. **Infrastructure first** — Docker, CI/CD, env vars, database connection
2. **Data layer second** — Schema conversion, Drizzle setup, migration scripts
3. **Auth third** — Better Auth setup, user migration, session strategy
4. **Core UI shell fourth** — Layout, navigation, routing in Next.js App Router
5. **Feature pages fifth** — Convert page by page, highest-traffic first
6. **Background jobs sixth** — Add BullMQ for existing async patterns
7. **Polish and cleanup last** — Remove old dependencies, dead code, legacy patterns

### For each phase, specify:

```markdown
## Phase N: [Name]

**Goal:** [What's working at the end of this phase]

**Prerequisites:** [Which phases must be done first]

**Steps:**
1. [Specific file/component/table to create or convert]
2. [...]

**Validation:**
- [ ] [How to verify this phase is complete]
- [ ] [What tests to run or behaviors to check]

**Risk / rollback:**
- [What could go wrong and how to recover]
```

### Data migration specifics

For the database migration phase, always include:
- Drizzle schema files derived from existing tables (mapped to DevHawk naming conventions)
- A data migration script or approach (pg_dump/restore if same DB engine, or ETL script if switching engines)
- How to handle foreign key relationships during cutover
- Whether the migration can be done with zero downtime (expand/contract) or requires a maintenance window

### Auth migration specifics

For the auth migration phase, always include:
- How to migrate existing user records into Better Auth's user/account/session tables
- Password hash compatibility (bcrypt hashes are portable; other algorithms may need rehashing on next login)
- How to handle active sessions during cutover (force re-login vs. parallel auth)
- Social login provider reconfiguration

## Phase 4: Generate backlog

Convert the migration plan into stories. Use the same epic/story structure as the bootstrap skill:

```
## Epic: M1 — [Phase name]
**Goal:** [End state]

### M1-S1: [Story title]
**As a** developer
**I want to** [migration step]
**So that** [what it enables]

**Acceptance criteria:**
- [ ] [Specific, testable outcomes]

**Migration notes:**
- [Source file/pattern] → [Target file/pattern]
- [Any gotchas or edge cases]
```

Use M-prefixed epic IDs (M1, M2, ...) to distinguish migration stories from feature stories.

If the Asana MCP is connected, offer to create these as tasks in an Asana project.

## Important guidelines

- **Never assume you can skip inspection.** Even if the user describes their stack, verify by reading the code. Users often forget about legacy patterns, dead code, or undocumented integrations.
- **Preserve business logic.** The goal is to change the technical substrate, not rewrite business rules. Extract and reuse wherever possible.
- **Identify the "hard parts" early.** The migration complexity is usually dominated by 2-3 areas. Call these out clearly so the user can plan resourcing.
- **Data is sacred.** Production data migration must be planned with extreme care. Always recommend a dry-run migration against a database copy before touching production.
- **Feature parity before new features.** The migration plan should achieve parity with the existing app first. New features come after migration is complete.
- **Parallel running when possible.** Recommend running old and new systems in parallel during cutover where feasible, especially for auth and data layers.
