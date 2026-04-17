# DevHawk App

## Commands
```
pnpm dev              # Start PG + Redis + web + worker (all-in-one via pm2)
pnpm dev:stop         # Stop all pm2 processes
pnpm dev:logs         # Tail pm2 logs (web + worker)
pnpm dev:status       # Show pm2 process table
pnpm worker:dev       # BullMQ worker (standalone, separate terminal)
pnpm build            # Production build
pnpm test             # Vitest watch mode
pnpm test:run         # Vitest single run
pnpm test:e2e         # Playwright E2E
pnpm lint             # ESLint + Biome
pnpm typecheck        # tsc --noEmit
pnpm db:generate      # Generate migration from schema changes
pnpm db:migrate       # Apply migrations
pnpm db:push          # Push schema (rapid prototyping only)
pnpm db:seed          # Populate database with realistic test data
pnpm db:studio        # Visual DB browser
```

## Stack
Next.js 16 App Router · Drizzle ORM · Better Auth · BullMQ · shadcn/ui · Tailwind v4 · Zod · Vitest · Playwright
Hosted on DO App Platform: Service (web) + Worker (BullMQ) + Job (cron/migrations) + Managed PG 16 + Managed Redis 7

## IMPORTANT: Read before writing code
@docs/conventions.md — Code patterns, naming, file organization, error handling. Non-negotiable.

## Reference docs (read when relevant to the current task)
- Stack decisions and rationale: @docs/architecture.md
- Database schema, queries, migrations, multi-tenancy: @docs/database-patterns.md
- Auth, social login, organizations, session handling: @docs/auth-patterns.md
- Background jobs, queues, BullMQ patterns: @docs/background-jobs.md
- AI agents, tool calling, streaming, structured outputs: @docs/ai-patterns.md
- Testing, Vitest, Playwright, what to test: @docs/testing-patterns.md
- Deployment, Docker, CI/CD, DO App Platform: @docs/deployment.md — read before provisioning or modifying infrastructure on DigitalOcean

## Tooling
- **Context7 MCP** — fetch up-to-date library docs on demand. Configured in `.mcp.json`. Use it instead of guessing when uncertain about a library's current API surface.
- **`/code-review`** — Anthropic's official code-review plugin (auto-enabled via `.claude/settings.json`). Run after non-trivial changes; five parallel agents check CLAUDE.md compliance, bugs, git context, and prior PR feedback.

## Key rules
- Server Components by default. Only add "use client" when hooks or event handlers are needed.
- Server Actions for mutations. API routes only for webhooks and external consumers.
- ALL external input validated with Zod. No exceptions.
- BullMQ for anything >500ms or that might fail (emails, AI calls, external APIs).
- Every database query in multi-tenant contexts MUST filter by organizationId.
- TypeScript strict mode. No `any` types.
- Import with `@/` path alias: `import { db } from "@/lib/db"`.
