# Architecture

## Stack decisions

Every choice in this stack was validated for Claude Code generation accuracy, operational simplicity, and cost-effectiveness. Do not substitute technologies without updating this document and the CLAUDE.md.

| Layer | Tool | Why this one |
|-------|------|-------------|
| Hosting | DO App Platform | Component model (Service/Worker/Job), no timeout on Workers, MCP server, ~$53/mo total |
| Framework | Next.js 16 App Router | Deepest Claude training data, Turbopack default, PPR stable, standalone Docker output |
| ORM | Drizzle | SQL-first (Claude generates accurate queries), no codegen, 7.4KB, native RLS support |
| Database | DO Managed PG 16 | Same VPC, PgBouncer pooling, pgvector, $15/mo |
| Redis | DO Managed Redis 7 | BullMQ queues, caching, rate limiting, sessions. Same VPC, $15/mo |
| Auth | Better Auth | Self-hosted, $0 at any scale, Drizzle adapter, 40+ social providers, org plugin for multi-tenancy |
| AI | Vercel AI SDK 6 | Provider-agnostic agents, streaming, structured outputs with Zod |
| UI | shadcn/ui + Tailwind v4 | Owned components, highest Claude accuracy, Radix primitives |
| Validation | Zod | End-to-end: forms, Server Actions, API routes, AI tools, DB schemas, env vars |
| State | Zustand + TanStack Query | Client (~1KB) + server cache. RSC handles most data flow. |
| Testing | Vitest + Playwright | Unit/integration + E2E/browser |
| Jobs | BullMQ + DO Jobs | Event-driven queues (BullMQ in Worker) + cron/deploy hooks (DO Jobs) |
| CI/CD | GitHub Actions | lint → typecheck → test → Docker build → GHCR → DO deploy |

## Component model

The app runs as multiple DO App Platform components sharing env vars and VPC:

- **Service (web)** — Next.js handling HTTP. Autoscalable. Adds jobs to BullMQ queues.
- **Worker (job-worker)** — BullMQ consumer. Always-on, no HTTP, no timeout. Processes queued work with retries.
- **Job (db-migrate)** — Pre-deploy hook. Runs `drizzle-kit migrate` before new containers start.
- **Database (db)** — Managed PostgreSQL 16 with PgBouncer.
- **Database (redis)** — Managed Redis 7 for BullMQ + caching.

## Data flow

1. User request → Next.js Service → Drizzle → PostgreSQL (synchronous)
2. User action needing async work → Service calls `queue.add()` → Redis → Worker picks up → processes with retries → writes result to PG
3. Scheduled work → DO Job component runs on cron → executes script → exits (billed per-run)
4. Deploy → DO Job (pre-deploy) runs `drizzle-kit migrate` → Service + Worker containers start with new code

## Key patterns

- Server Components for data fetching (no client-side waterfall)
- Server Actions for mutations (form submissions, state changes)
- API routes only for webhooks, external API consumers, and auth callbacks
- BullMQ for anything that takes >500ms or might fail (emails, AI calls, exports, external APIs)
- DO Jobs for scheduled work (nightly cleanup, report generation, cache warming)

## DigitalOcean organization

Resources roll up to DO Projects by **product** (one project per product like Example_1, Example_2). Use **tags** for environment (`env:prod`, `env:staging`) and optionally role (`role:web`, `role:db`, `role:cache`). DO's billing CSV exports include both project and tags as columns, so you can pivot to "what's product X costing me" or "what's staging across all products costing me."
