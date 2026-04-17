# DevHawk Features

## Skills

Skills are loaded automatically by Claude Code when triggered by context. They provide guided workflows for common tasks.

### `bootstrap`
Turns a product idea into a running project. Runs an interactive discovery conversation (~10 min) covering users, data, auth, multi-tenancy, AI, integrations, and aesthetic direction. Then generates database schema, routes, auth config, background jobs, a distinctive visual design (using the `frontend-design` skill), test stubs, and a project-specific CLAUDE.md. Creates a backlog of epics and stories, then provisions GitHub repo, Asana project, and optionally a DO App Platform app.

**Trigger:** "bootstrap", "new project", "start a new app", "build a new product", "scaffold"

### `migrate`
Analyzes an existing codebase and produces a phased migration plan to the DevHawk stack. Inspects every layer (framework, database, auth, UI, jobs, infrastructure), presents a complexity assessment, then generates an ordered migration plan and backlog. Each phase leaves the app in a working state — no big-bang cutovers.

**Trigger:** "migrate this app", "migration plan", "move to devhawk", "convert this codebase", "port this to our stack"

### `feature-build`
Guides implementation of a single feature or user story. Follows a structured checklist: schema, server logic, background jobs, UI, auth guards, tests, verification. Uses the `frontend-design` skill for user-facing pages and components to maintain the project's established aesthetic direction. Includes patterns for CRUD features, AI features, and webhook handlers.

**Trigger:** "build [feature]", "implement [story]", "work on E2-S3", or any request to implement a story

### `seed-data`
Generates a `lib/db/seed.ts` script with realistic test data tailored to the project's domain, schema, and business rules. Creates diverse users with working auth credentials, multi-tenant org data (if applicable), and domain entities with realistic names, dates, values, and relationships. Idempotent — safe to run repeatedly. Run with `pnpm db:seed`.

**Trigger:** "seed data", "test data", "sample data", "populate the database", "I need data to test with"

### `devhawk-stack`
Knowledge base for architectural decisions. Answers questions about why specific technologies were chosen, what alternatives were considered, cost comparisons, and when it's appropriate to deviate from the reference stack.

**Trigger:** "why do we use Drizzle", "how much does this cost", "should we use X instead of Y"

## Commands

Commands are invoked explicitly with a `/` prefix in Claude Code.

### `/devhawk-new <project-name>`
Clones the seed repo, removes git history, installs dependencies, starts PostgreSQL + Redis via Docker, copies environment config, runs migrations, and verifies typecheck. After completion, prompts you to say "bootstrap" to begin product discovery.

### `/provision`
Creates GitHub repo, Asana project, and DO App Platform app for a project that was bootstrapped but not yet provisioned. Runs pre-flight checks, degrades gracefully if tools are unavailable, and provides manual instructions for anything it can't automate.

## Progressive Disclosure Docs

Claude Code loads these on demand based on the task at hand. They live in `docs/` and are referenced from CLAUDE.md.

| Document | When it's loaded |
|----------|-----------------|
| `conventions.md` | Before writing any code (includes UI design principles) |
| `architecture.md` | Stack decisions and rationale questions |
| `database-patterns.md` | Schema, queries, migrations, multi-tenancy |
| `auth-patterns.md` | Auth, social login, organizations, sessions |
| `background-jobs.md` | BullMQ queues, job processing |
| `ai-patterns.md` | AI SDK agents, tools, streaming |
| `testing-patterns.md` | Vitest, Playwright, what to test |
| `deployment.md` | Docker, CI/CD, DO App Platform |

## Enforcement Hooks

These run automatically after file edits to catch issues early:

- **TypeScript typecheck** — runs `tsc --noEmit` after every Write/Edit
- **Auto-generate migration** — runs `drizzle-kit generate` when schema files change

## Integrations

### GitHub (`gh` CLI)

DevHawk uses the GitHub CLI for repository management throughout the project lifecycle.

- **Repo creation** — `bootstrap` and `/provision` create private repos in the `fractionwork` org, set the remote, and push the scaffold to `main`
- **CI/CD pipeline** — GitHub Actions runs lint, typecheck, and tests on every PR. On merge to `main`, it builds Docker images, pushes to GHCR, and triggers deployment to DO App Platform
- **PR workflow** — Claude Code creates branches, commits, and opens PRs with structured descriptions during feature development

**Setup:** `gh auth login` (one-time, verified by the install script)

### Asana (MCP server)

DevHawk connects to Asana via the official MCP server for automated project management.

- **Project creation** — `bootstrap` and `/provision` create an Asana project with board layout (Backlog / Ready / In Progress / Review / Done sections)
- **Backlog population** — Epics are created as tasks, stories as subtasks with user story format, acceptance criteria, and story point estimates
- **Migration backlogs** — The `migrate` skill generates M-prefixed migration stories and can push them to Asana
- **Feature tracking** — `feature-build` references story IDs (e.g., "build E2-S3") that map to Asana subtasks

**Setup:** Create an MCP app in the [Asana developer console](https://app.asana.com/0/my-apps), then connect via:
```bash
claude mcp add --transport http \
  --client-id YOUR_CLIENT_ID \
  --client-secret \
  --callback-port 8080 \
  asana https://mcp.asana.com/v2/mcp
```

### DigitalOcean (`doctl` CLI)

DevHawk uses the DigitalOcean CLI to provision and manage production infrastructure.

- **App creation** — `bootstrap` and `/provision` create a DO App Platform app from `app.yaml`, which declares the full component model (Service, Worker, Job, managed PostgreSQL, managed Redis)
- **AppSpec management** — The `app.yaml` is updated with project-specific names during scaffold generation and committed to the repo
- **Deployment** — After CI builds Docker images and pushes to GHCR, DO App Platform detects new images and deploys automatically. The pre-deploy Job runs database migrations before new containers start.
- **Rollback** — `doctl apps list-deployments` and the DO dashboard provide rollback to any of the last 10 deployments

**Setup:** `doctl auth init` with a [DO API token](https://cloud.digitalocean.com/account/api/tokens) (one-time, verified by the install script)

### Docker

Docker provides local backing services and production container builds.

- **Local development** — `docker compose -f docker/docker-compose.dev.yml up -d` starts PostgreSQL 16 and Redis 7 in the same configuration as production
- **Production images** — Multi-stage Dockerfiles for the web service (`docker/Dockerfile`) and worker (`docker/Dockerfile.worker`). Web uses Next.js standalone output (~150-200MB). Worker runs tsx directly.
- **CI builds** — GitHub Actions builds both images, tags with commit SHA, and pushes to GHCR

**Setup:** Docker Desktop (macOS) or Docker Engine (Linux)

### PM2

PM2 manages the local dev environment as a single command instead of multiple terminals.

- **`pnpm dev`** — Starts Docker services (PG + Redis), Next.js dev server, and BullMQ worker
- **`pnpm dev:logs`** — Tails combined output from both processes
- **`pnpm dev:status`** — Shows process table with uptime and memory
- **`pnpm dev:stop`** — Stops all processes

The `ecosystem.config.cjs` loads `.env.local` automatically for both processes.

### Frontend Design (Claude Code plugin)

The `frontend-design` plugin prevents generic "AI slop" aesthetics by enforcing intentional design choices during UI generation.

- **Bootstrap** — After the user describes their aesthetic direction (brutalist, editorial, luxury, etc.), the skill generates a distinctive theme: typography pairing, color system, motion patterns, and spatial composition
- **Feature build** — User-facing pages and components are built matching the project's established design language
- **Conventions** — UI design principles are baked into `docs/conventions.md` so they apply even without the plugin: no default Inter/Roboto, no purple-on-white gradients, no cookie-cutter layouts

**Setup:** `claude plugins install frontend-design` (or install from the Claude Code plugin marketplace)

### Graceful degradation

All integrations are optional. If `gh`, `doctl`, or Asana MCP are not available, skills will:
- Skip the automated step
- Write equivalent output locally (e.g., backlog saved to `backlog.md`)
- Provide manual instructions for completing the step

---

## Workflows

### New project from scratch

This is the primary workflow. You have a product idea and want a running app with backlog.

```
1.  /devhawk-new my-project          # Clone seed, install deps, start services
2.  bootstrap                         # Discovery conversation (~10 min)
                                      #   → Claude asks about users, data, auth, AI,
                                      #     integrations, multi-tenancy, aesthetic direction
3.  [answer questions, confirm plan]  # Claude generates scaffold:
                                      #   → Distinctive theme (typography, colors, motion)
                                      #   → Database schema + migrations
                                      #   → Route stubs + styled auth pages
                                      #   → Better Auth config (with/without orgs)
                                      #   → BullMQ queues + processors
                                      #   → Test stubs
                                      #   → CLAUDE.md addendum + README
4.  [confirm provision]               # Claude creates:
                                      #   → GitHub repo (fractionwork org)
                                      #   → Asana project with epics/stories
                                      #   → DO App Platform app (optional)
5.  pnpm dev                      # Start web + worker
6.  build E1-S1                       # Pick a story, start building
```

### Migrate an existing app

You have an existing codebase and want to move it to the DevHawk stack.

```
1.  cd /path/to/existing-app
2.  migrate                           # Claude inspects the codebase:
                                      #   → Framework, database, auth, UI, jobs, infra
                                      #   → Presents migration complexity matrix
3.  [confirm assessment]              # Claude generates:
                                      #   → Phased migration plan (each phase is deployable)
                                      #   → Migration backlog (M-prefixed epics/stories)
                                      #   → Optionally populates Asana
4.  /devhawk-new my-project           # Set up the target project
5.  [work through migration phases]   # Phase order:
                                      #   → Infrastructure (Docker, CI/CD, env vars)
                                      #   → Data layer (Drizzle schema, data migration)
                                      #   → Auth (Better Auth, user migration)
                                      #   → UI shell (Next.js App Router, layout, nav)
                                      #   → Feature pages (convert page by page)
                                      #   → Background jobs (BullMQ)
                                      #   → Cleanup (remove legacy deps)
```

### Build a feature on an existing DevHawk project

You have a running DevHawk project and want to implement a story from the backlog.

```
1.  cd my-project
2.  pnpm dev                      # Start web + worker
3.  build E2-S3                       # Or describe the feature
                                      #   → Claude reads conventions + relevant docs
                                      #   → Implements schema → server logic → UI → tests
                                      #   → UI matches project aesthetic (frontend-design)
                                      #   → Runs typecheck + tests
4.  [review, iterate]
5.  /commit                           # When ready
```

### Ask about the stack

You want to understand why a technology was chosen or evaluate an alternative.

```
1.  why do we use Better Auth instead of Clerk?
2.  how much does the infrastructure cost?
3.  should we use Inngest instead of BullMQ for this use case?
```

Claude loads the `devhawk-stack` knowledge base and answers with rationale, cost comparisons, and guidance on when to deviate.
