---
name: bootstrap
description: >
  Bootstrap a new DevHawk project from a product idea or business problem.
  Runs an interactive discovery conversation, maps features to stack components,
  generates scaffold code on the seed repo, creates CLAUDE.md addendum,
  generates backlog, and optionally provisions GitHub repo + Asana project +
  DO App Platform app. Triggers on phrases like "new project", "bootstrap",
  "start a new app", "build a new product", "scaffold", "set up a project for",
  or any request to create a new application on the DevHawk stack.
---

# DevHawk Project Bootstrap

You are setting up a new project on the DevHawk Reference Stack. The stack is already decided — do NOT evaluate technologies. Focus entirely on understanding the PRODUCT and mapping features to stack components.

The full pipeline runs in four phases, all within this single Claude Code session:

1. **Discovery** — Understand the product (interactive, ~10 min)
2. **Scaffold** — Generate code on the seed repo (automated)
3. **Backlog** — Create epics, stories, tasks (automated)
4. **Provision** — GitHub repo + Asana project + DO app (automated, requires confirmation)

### Auto-accept mode

If the builder says any of: "auto", "auto-accept", "just run it", "skip confirmations", "don't ask, just do it" — or passes `--auto` as an argument — enable **auto-accept mode**. Acknowledge it immediately:

> **Auto-accept is on.** After the discovery rounds (which still need your input), I'll show the architecture review and each provisioning step but proceed without waiting for approval. Say **"stop"** or **"hold on"** at any point to pause and switch back to interactive mode.

In auto-accept mode:
- **Phase 1 discovery rounds** — still interactive (these require the builder's answers; can't auto-accept input)
- **MVP scope check** — shown, then proceed without waiting
- **Architecture review** — shown in full (builder can scan it), then proceed without waiting. If the builder interrupts with a question or change request, pause, address it, and resume auto-accept
- **Phase 2 scaffold** — runs without confirmation (it's code generation — reversible via git)
- **Phase 3 backlog** — runs without confirmation
- **Phase 4 provisioning** — runs each step sequentially without asking. GitHub repo creation, Asana/Jira backlog, AppSpec rename, and DO deploy handoff all proceed. The builder still sees what's happening (show each step's output) but doesn't need to approve each one

**The only hard pause in auto-accept mode** is if something fails (typecheck error, `doctl` auth issue, `gh` repo creation error). On failure, stop, report the error, and wait — don't retry or skip.

If auto-accept is NOT enabled (the default), all existing approval gates remain: explicit approval at architecture review, per-step confirmation in Phase 4, etc. The default is the careful path.

---

## Phase 1: Product discovery (interactive)

Discovery runs as a **conversation in rounds**, not a questionnaire. Each round is a small group of related questions — wait for answers before moving to the next. Build on what you learn; skip what's already answered. Use multiple-choice options wherever possible so the builder can answer quickly and unambiguously, with a free-text fallback when the options don't fit.

**Goal:** cover all the topics below across 4 rounds, taking ~10 minutes total. Do NOT dump all questions at once. Do NOT ask one question at a time (too slow). 3-5 questions per round is the sweet spot.

**IMPORTANT — AskUserQuestion visibility workaround:** The AskUserQuestion tool's UI can render with poor contrast on dark terminals (black text on dark background). To ensure the builder always sees the full context:

1. **Always output the questions and options as regular text FIRST** — write them out as a numbered list with the options lettered, in your normal response. This renders in the terminal's default (readable) font color.
2. **Then call AskUserQuestion** as the interactive picker. Keep the `question` field short (one line) and rely on option `label` + `description` for the details.
3. The builder can answer via either the AskUserQuestion UI picker OR by typing their answer in the chat — both work. The text output ensures they can read the question regardless of terminal theme.

This pattern applies to every AskUserQuestion call in discovery AND the architecture review sections.

If the builder provides a spec, PRD, or description upfront, acknowledge what it already tells you ("Based on the doc, I see X — correct?") rather than re-asking from scratch. But DO still confirm every architectural decision explicitly — specs often omit multi-tenancy, auth details, async work, observability, and aesthetic direction.

Do NOT ask about tech stack, hosting, or architecture — those are decided.

### Round 1: Product + users

Start by reading whatever the builder provided. Then respond with:

1. **What I'm hearing** — 2-3 sentences on what this product is, who it's for, what problem it solves
2. **Initial feature map** — your best guess at the major features, as a bulleted list
3. **Stack conflicts** — if the description mentions technologies that differ from the DevHawk stack (e.g. "use Firebase", "deploy on Vercel"), call them out and ask if they're hard requirements or soft preferences

Then use the **AskUserQuestion** tool for the structured questions:

```
AskUserQuestion with 2 questions:

  Question 1 (single-select):
    header: "User type"
    question: "Who uses this product?"
    options:
      - "Internal tool" — "Known users, predictable load, behind company auth"
      - "B2B SaaS" — "Business customers with team accounts (multi-tenant)"
      - "Consumer app" — "Public sign-up, individual users"
      - "Marketplace" — "Multiple user types (buyers + sellers, hosts + guests, etc.)"

  Question 2 (single-select):
    header: "Multi-tenant"
    question: "Will teams/organizations each see only their own data?"
    options:
      - "Yes — org isolation" — "Every table gets organizationId, every query filters by it. Needed for B2B SaaS, agency tools, team platforms."
      - "No — flat access" — "Single-user or flat roles. No organization-scoped data."
      - "Not sure" — "Describe your access model and I'll recommend"
```

After the builder answers, follow up in text: *"Walk me through the main thing a user does — 3-5 steps, plain English."* (This is inherently open-ended; no good options to offer.)

Wait for the workflow answer. After this round, you know the product shape, the user model, and the tenancy decision.

### Round 2: Data + integrations

Build on Round 1. Show the builder what you've derived so far:

> Based on your answers, here are the main entities I see:
> - [Entity] — [fields, relationships]
> - [Entity] — ...
> What am I missing? Anything named wrong?

Then use **AskUserQuestion** for the structured parts:

```
AskUserQuestion with 3 questions:

  Question 1 (multiSelect: true):
    header: "Auth"
    question: "Which auth methods does this project need?"
    options:
      - "Email + password" — "Standard email/password sign-up and login"
      - "Google sign-in" — "OAuth social login via Google"
      - "SSO / SAML" — "Enterprise single sign-on for larger customers"
      - "Two-factor (2FA)" — "TOTP-based second factor for sensitive accounts"
    (Other covers: GitHub, Apple, passkeys, API keys, magic links)

  Question 2 (multiSelect: true):
    header: "Integrations"
    question: "Which external services will this project use?"
    options:
      - "Stripe" — "Payment processing, subscriptions, invoicing"
      - "Resend" — "Transactional email (welcome, reset, notifications)"
      - "Other API" — "A third-party API not listed — describe in notes"
      - "None yet" — "No external integrations in MVP"

  Question 3 (single-select):
    header: "AI"
    question: "Does this product use AI?"
    options:
      - "None" — "No AI features in MVP"
      - "Chat assistant" — "Conversational UI, streaming responses"
      - "Content analysis" — "Document/data analysis, classification, extraction"
      - "Agent with tools" — "Multi-step reasoning, function calling, autonomous workflows"
```

Wait for answers. After this round, you know the data model, auth surface, integrations, and AI scope.

### Round 3: Infrastructure + ops

Short round. Skip questions the builder already answered. Use **AskUserQuestion**:

```
AskUserQuestion with 3 questions:

  Question 1 (multiSelect: true):
    header: "Async work"
    question: "What background work does this product need?"
    options:
      - "Transactional emails" — "Welcome, reset, notifications via BullMQ + Resend"
      - "Webhook processing" — "Stripe webhooks, external service callbacks"
      - "Data exports" — "Report generation, CSV/PDF exports, long-running queries"
      - "AI processing" — "Long-running AI calls queued via BullMQ"
    (Other covers: scheduled/cron jobs, custom async work, or "none")

  Question 2 (single-select):
    header: "Environments"
    question: "How many environments do you need?"
    options:
      - "Prod only (~$45/mo)" — "Single environment, simplest setup"
      - "Prod + staging, shared clusters (~$60/mo) (Recommended)" — "Staging shares prod's PG + Valkey clusters with logical isolation. Best for pre-launch."
      - "Prod + staging, separate clusters (~$90/mo)" — "Full physical isolation. Recommended once prod has real users or sensitive data."

  Question 3 (single-select):
    header: "Observability"
    question: "Include OpenObserve + OpenTelemetry for traces, structured logs, and metrics?"
    options:
      - "Yes" — "Adds OpenObserve to Docker Compose, OTel auto-instrumentation, Pino logger with trace correlation"
      - "No, add later" — "Skip for now — can be added to any project later without schema changes"
```

After the AskUserQuestion answers, confirm the DO Project name in text: *"DO Project name for cost attribution defaults to `[ProjectName]`. Change it, or Enter to accept."*

Wait for answers. After this round, infrastructure decisions are locked.

### Round 4: Look and feel

Push for specifics — "clean and modern" is what every AI generates by default; the `frontend-design` skill needs a strong direction. Use **AskUserQuestion**:

```
AskUserQuestion with 3 questions:

  Question 1 (single-select):
    header: "Aesthetic"
    question: "What visual direction should this product have?"
    options:
      - "Minimal" — "Stark white space, sharp typography, restrained palette. Think: Linear, Notion."
      - "Refined / luxury" — "Muted tones, elegant serif, generous spacing. Think: Stripe, Aesop."
      - "Playful" — "Rounded shapes, bold colors, bouncy motion. Think: Figma, Loom."
      - "Industrial" — "Data-dense, compact, tooling-first. Think: Grafana, Datadog."
    (Other covers: brutalist, editorial, art deco, retro-futuristic, soft/pastel, or a reference app)

  Question 2 (single-select):
    header: "Dark mode"
    question: "Dark mode support?"
    options:
      - "Light only" — "Single light theme"
      - "Dark only" — "Single dark theme"
      - "Both" — "System-preference toggle with light + dark themes"

  Question 3 (single-select):
    header: "Navigation"
    question: "Primary navigation pattern?"
    options:
      - "Sidebar" — "Fixed left sidebar — best for data-heavy dashboards with many sections"
      - "Top nav" — "Horizontal navigation bar — best for content-focused or marketing-oriented apps"
```

After the AskUserQuestion answers, follow up in text: *"Brand colors? (describe, paste hex, or 'surprise me within the aesthetic') Fonts? (name favorites, or 'pick something that fits')"*

Wait for answers.

### After all 4 rounds

Before producing the architecture review, briefly summarize what you'll defer. Use **AskUserQuestion** one final time to confirm scope:

```
AskUserQuestion with 1 question:

  Question 1 (single-select):
    header: "MVP scope"
    question: "Here's what I'd put in MVP vs. v2. [List MVP items] will ship first. [List v2 items] will wait. Agree?"
    options:
      - "Looks right" — "Proceed with this scope split"
      - "Move something to MVP" — "I'll describe what should move up"
      - "Move something to v2" — "I'll describe what should be deferred"
      - "Let's discuss" — "I have questions about the scope"
```

Wait for the builder to confirm the scope split. Then produce the architecture review (next section).

### Checkpoint — Architecture review (4 sections, progressive approval)

The architecture review covers everything the scaffold will generate. Instead of presenting it as one massive block, break it into **4 sections** ��� each shown, reviewed, and approved before moving to the next. This matches the discovery-round pattern: the builder stays engaged and catches problems early rather than scanning 80 lines at the end.

**Do not generate any code until all 4 sections are approved.** Reshaping the design here is cheap; reshaping a generated scaffold is expensive.

**Auto-accept:** show all sections in one pass. Otherwise: show → approve → next.

Output each section as text first (terminal-readable), then AskUserQuestion as picker.

#### 1. Project identity

> **[Name]** — [one-liner]
> Repo: `[slug]` · DO Project: `[ProductName]` · Team: `[team-slug]`

AskUserQuestion — header: "Project", question: "Correct?", options: "Yes" / "Change"

#### 2. Users + auth

> **Roles:** [role → one-line description, per line]
> **Multi-tenant:** yes (orgId on all tables) / no
> **Auth:** [comma-separated list]

AskUserQuestion — header: "Auth", question: "Correct?", options: "Yes" / "Change"

#### 3. Data model

Compact table, no prose:

> | File | Table | Key fields | Relations |
> |------|-------|------------|-----------|
> | `product.ts` | `product` | name, price, active | → org, → user |
> | `order.ts` | `order` | status, total | → org, → product |
> | *(seed auth tables: user, session, account, org, member)* |

AskUserQuestion — header: "Schema", question: "Correct?", options: "Yes" / "Change" / "Add table" / "Go back"

#### 4. Actions + routes

> **Actions:** `createProduct`, `updateOrder`, `inviteMember` *(grouped by domain)*
> **Routes:** `/api/webhooks/stripe`, `/api/auth/[...all]`, `/api/bootstrap`
> **Protected:** `/dashboard/*`, `/admin/*`

AskUserQuestion — header: "Server", question: "Correct?", options: "Yes" / "Change" / "Go back"

#### 5. Queues + AI + integrations

> **Queues:** `email` → transactional, `export` → PDF/CSV *(one line each)*
> **AI:** [provider + pattern] or none
> **Services:** Stripe, Resend *(or none)*

AskUserQuestion — header: "Async", question: "Correct?", options: "Yes" / "Change" / "Go back"

#### 6. Infrastructure

> **Envs:** prod / prod+staging shared ($60) / prod+staging separate ($90)
> **Compute:** web basic-xs · worker basic-xxs · migrate basic-xxs
> **Clusters:** PG `[slug]-db` · Valkey `[slug]-valkey` · nyc3
> **PG users:** `[slug]_prod` → defaultdb · `[slug]_staging` → `[slug]_staging`
> **Branches:** main=prod · develop=staging
> **Local:** PG :[port] · Valkey :[port] · compose name: `[slug]`
> **Observability:** yes / no

AskUserQuestion — header: "Infra", question: "Correct?", options: "Yes" / "Change" / "Go back"

#### 7. UX + deferred → generate

> **Aesthetic:** [vibe] · **Fonts:** [display]/[body] · **Colors:** [palette]
> **Dark:** yes/no/both · **Nav:** sidebar/top
> **v2:** [deferred items]

AskUserQuestion — header: "Generate", question: "Ready?", options: "Generate" / "Change UX" / "Move scope" / "Go back"

"Generate" → Phase 2 starts.

---

## Phase 2: Scaffold generation

After confirmation, generate the following ON TOP of the existing seed repo files.

Read @docs/conventions.md before generating any code.

### Docker isolation (`docker/docker-compose.dev.yml`, `.env.local`)

Each project MUST have unique Docker resource names so multiple projects can run simultaneously. Update `docker/docker-compose.dev.yml`:

1. Add `name: [project-name]` at the top level (Compose project name — prefixes all containers and networks)
2. Change `POSTGRES_DB`, `POSTGRES_USER` to use the project name (e.g., `rateiq` instead of `devhawk`)
3. Assign unique host ports to avoid collisions. Use a deterministic offset based on the project name so ports are stable across restarts. Pick from ranges: PG 5433-5499, Redis 6380-6499, OpenObserve 5081-5099. Example for a project:
   - PostgreSQL: `"5433:5432"`
   - Redis: `"6380:6379"`
   - OpenObserve (if enabled): `"5081:5080"`
4. Update the `healthcheck` test to use the new username

Then update `.env.local` and `.env.example` so `DATABASE_URL` and `REDIS_URL` reflect the new ports and credentials:
```
DATABASE_URL="postgresql://[project-name]:[project-name]_local@localhost:[pg-port]/[project-name]"
REDIS_URL="redis://localhost:[redis-port]"
```

Also update `drizzle.config.ts` default fallback if it hardcodes port 5432.

### Theme and layout (`app/globals.css`, `app/layout.tsx`)

**Invoke the `frontend-design` skill with the UX direction from Phase 1's architecture review as explicit, structured input.** Do not let the skill re-derive or guess — hand it the approved values directly:

```
Invoke frontend-design with:
- Aesthetic direction: [approved vibe from architecture review]
- Display font: [font name + source: Google Fonts / local]
- Body font: [font name + source]
- Color palette: [dominant colors + sharp accents, as HSL]
- Light/dark/both: [decision]
- Nav pattern: [sidebar / top nav]
- Primary surfaces to restyle: globals.css @theme block, app/layout.tsx,
  app/(auth)/sign-in + sign-up, app/(dashboard)/layout.tsx
```

The goal is a distinctive, cohesive aesthetic — not a generic template. Read @docs/conventions.md for UI design principles.

Handing the skill pre-decided inputs is the difference between a result that matches the builder's review-time intent and one that drifts mid-generation. If any of these values weren't captured during architecture review, go back and ask — don't proceed with "I'll pick".

Based on the UX direction from discovery:

- **Aesthetic direction:** Commit to the specific vibe the user described. If they said "luxury/refined," every detail should reinforce that — typography, spacing, color, motion. If they said "brutalist/raw," lean into it with confidence. Half-measures produce generic results.
- **Typography:** Choose a distinctive display font + complementary body font via `next/font/google` or `next/font/local`. Do NOT default to Inter — pick something that reinforces the aesthetic. Update the font variable in `layout.tsx`.
- **Color scheme:** Update CSS custom properties in `globals.css` `@theme` block. Use HSL values for all color tokens. Dominant colors with sharp accents — don't distribute colors timidly across the palette.
- **Dark mode:** If requested, add dark mode variants in `globals.css` under a `.dark` selector and add a theme toggle component. The seed includes `@variant dark (&:is(.dark *))` ready for this.
- **Navigation:** Based on preference (sidebar vs top nav), create the appropriate shell layout in `app/(dashboard)/layout.tsx`. Sidebar for data-heavy/dashboard apps, top nav for content/marketing-oriented apps.
- **Auth pages:** Restyle the sign-in/sign-up pages in `app/(auth)/` to match the chosen aesthetic. These are the first thing users see — they set the tone.
- **Motion:** Add purposeful transitions for page loads and state changes. One well-orchestrated entrance animation creates more delight than scattered micro-interactions.

If no strong preferences were expressed, keep the seed defaults but still choose a distinctive font. These can always be refined later.

### Database schema (`lib/db/schema/[domain].ts`)
- One file per domain (products.ts, orders.ts, etc.)
- Follow patterns in @docs/database-patterns.md
- Include organizationId on all tenant-scoped tables
- Add export to `lib/db/schema/index.ts`
- Generate Zod validation schemas alongside each table

### Route stubs (`app/`)
- Page files with basic layout and placeholder content
- Route groups: `(auth)` for login/signup, `(dashboard)` for authenticated pages
- API routes only for webhooks and external consumers
- Loading and error boundary files for key routes

### Better Auth config updates (`lib/auth.ts`, `lib/auth-client.ts`, `lib/db/schema/auth.ts`)
- Activate required social providers (uncomment + add env vars to `.env.example`)
- Add required plugins (passkey, magicLink, stripe, apiKey, etc.)
- Update `lib/auth-client.ts` with matching client plugins

**If multi-tenant (organizations enabled):**
- Keep the `organization()` plugin in `lib/auth.ts` and `organizationClient()` in `lib/auth-client.ts`
- Keep `organizations`, `members`, `invitations` tables in `lib/db/schema/auth.ts`
- Keep `activeOrganizationId` on the `sessions` table
- All app data tables MUST include `organizationId` column with a foreign key to `organizations.id`
- All queries MUST filter by `session.session.activeOrganizationId`

**If NOT multi-tenant:**
- Remove the `organization()` plugin from `lib/auth.ts` and `organizationClient()` from `lib/auth-client.ts`
- Remove `organizations`, `members`, `invitations` tables from `lib/db/schema/auth.ts`
- Remove `activeOrganizationId` from the `sessions` table
- Remove `useActiveOrganization`, `useListOrganizations` exports from `lib/auth-client.ts`
- Do NOT add `organizationId` to app data tables
- Remove the org-related key rule from `CLAUDE.md` ("Every database query in multi-tenant contexts MUST filter by organizationId")

### BullMQ queue definitions (`lib/jobs/`)
- Add queue declarations in `queues.ts`
- Create processor files in `lib/jobs/processors/[queue-name].ts`
- Register workers in `worker.ts`

### AI agent definitions (`lib/ai/`)
- Tool definitions with Zod parameter schemas
- Agent configurations
- Chat route handler if needed

### Observability (if user opted in)

Only include this if the user said yes to observability during discovery. Skip entirely if they declined.

**Docker Compose** — Add OpenObserve to `docker/docker-compose.dev.yml`:
```yaml
openobserve:
  image: public.ecr.aws/zinclabs/openobserve:latest
  ports:
    - "5080:5080"
  environment:
    ZO_ROOT_USER_EMAIL: "dev@localhost"
    ZO_ROOT_USER_PASSWORD: "devhawk123"
    ZO_DATA_DIR: "/data"
  volumes:
    - openobserve_data:/data
```
Add `openobserve_data:` to the volumes section.

**Dependencies** — Add to `package.json`:
```
@opentelemetry/sdk-node
@opentelemetry/auto-instrumentations-node
@opentelemetry/exporter-trace-otlp-http
@opentelemetry/exporter-logs-otlp-http
@opentelemetry/api
pino
pino-opentelemetry-transport
```

**Instrumentation** — Create `app/instrumentation.ts` (Next.js auto-loads this):
```typescript
export async function register() {
  if (process.env.NEXT_RUNTIME === "nodejs") {
    await import("@/lib/telemetry");
  }
}
```

**Telemetry config** — Create `lib/telemetry.ts`:
- Initialize OpenTelemetry NodeSDK with auto-instrumentations
- OTLP trace exporter pointing at `OTEL_EXPORTER_OTLP_ENDPOINT` (default: `http://localhost:5080/api/default`)
- OTLP log exporter for structured logs
- Service name from `OTEL_SERVICE_NAME` env var

**Logger** — Create `lib/logger.ts`:
- Pino logger with `pino-opentelemetry-transport` for trace-correlated structured logs
- Export a `logger` instance used across Service and Worker
- In development, also log to stdout in pretty format

**Worker** — Update `lib/jobs/worker.ts` to import `@/lib/telemetry` at the top so OTel instruments the worker process.

**Environment** — Add to `.env.example`:
```
OTEL_EXPORTER_OTLP_ENDPOINT="http://localhost:5080/api/default"
OTEL_SERVICE_NAME="[project-name]"
```

**Dashboard access** — OpenObserve UI at `http://localhost:5080` with credentials `dev@localhost` / `devhawk123`.

### DO App Platform AppSpec (`app.yaml`, optional `app.staging.yaml`)

The seed ships with `app.yaml` (prod) and `app.staging.yaml` (staging-on-shared-clusters) using `<PROJECT_NAME>` placeholders. Sed-replace the placeholders with the project slug:

```bash
sed -i "s|<PROJECT_NAME>|[project-slug]|g" app.yaml app.staging.yaml .github/workflows/ci.yml
```

Then:
- **If multi-env:** leave both files in place. The `deploy-staging` job in `.github/workflows/ci.yml` is gated on `github.ref == 'refs/heads/develop'` and only fires when a `develop` branch is pushed.
- **If single-env:** delete `app.staging.yaml` and remove the `deploy-staging` job from `.github/workflows/ci.yml`. Do NOT leave dormant staging infrastructure declared — it's confusing and will bit-rot.

The seed's `lib/jobs/queues.ts` and `lib/jobs/worker.ts` already read `BULLMQ_PREFIX` from env (default `bull`). Staging overrides to `bull:staging` via `app.staging.yaml`. No scaffold action needed here — the pattern is baseline.

The DO Project (`<ProductName>`) and the managed PG + Valkey clusters are NOT created during scaffold. They're provisioned in Phase 4 via the `do-deploy` skill.

### Test stubs (`tests/`)
- Vitest files with describe blocks matching features
- Playwright spec files for critical user flows
- Empty test bodies with TODO comments describing what to test

### CLAUDE.md addendum
Add a project-specific section at the TOP of CLAUDE.md (before the generic stack section):

```markdown
# [Project Name]

[One-liner description]

## Domain concepts
- [Entity]: [What it is, key fields]
- [Entity]: [What it is, relationships]

## Business rules
- [Rule that affects implementation]
- [Validation constraint]

## Build order (recommended)
1. [First epic — usually auth + core data model]
2. [Second epic — core workflow]
3. [Third epic — integrations]
4. [Fourth epic — polish + edge cases]
```

### Update README.md

Replace the seed repo README with a project-specific one. The README should include:

```markdown
# [Project Name]

[One-liner description]

## Architecture

[Keep the mermaid component diagram from the seed README but update labels if the project
adds queues, workers, or external services beyond the defaults]

## Local development

### Prerequisites
- Node.js 22+
- pnpm (via corepack)
- Docker (for PostgreSQL + Redis)

### Setup
\```bash
git clone git@github.com:fractionwork/[project-name].git
cd [project-name]
pnpm install
docker compose -f docker/docker-compose.dev.yml up -d
cp .env.example .env.local
# Edit .env.local with your values
pnpm db:generate
pnpm db:migrate
pnpm dev          # Starts PG + Redis + web + worker
\```

## Scripts
[Table of pnpm scripts from CLAUDE.md — dev, build, test, lint, typecheck, db:*, worker:*]

## Stack
[Stack table from seed README]

## Project structure
[Brief description of key directories and what lives where, based on the generated scaffold]
```

Remove all seed-specific content: the `/devhawk-new` workflow, "What's in the seed" section,
provisioning details, manual setup from seed instructions, and the install-global-command references.
The README should read as if this project was always its own thing.

### Post-scaffold review

After typecheck passes, run `/code-review` against the generated scaffold. The plugin's CLAUDE.md-compliance agent will catch convention drift in the generated code (missing `organizationId` on tenant tables, `any` types, mutation API routes that should be Server Actions, etc.). Address high-confidence findings before moving to Phase 3.

### Post-scaffold verification

After generating all files, this is where Docker starts for the first time — with the project-specific compose project, DB user, and port mappings already in place. `/devhawk-new` only pulled the images; it deliberately didn't start containers to avoid collisions with other seed-based projects. The `down` below is a defensive no-op in the normal flow; it only matters if the user manually started containers earlier.

```bash
docker compose -f docker/docker-compose.dev.yml down   # Defensive: tear down if any seed-default containers are somehow running
docker compose -f docker/docker-compose.dev.yml up -d   # First real start — project-specific names/ports
# Wait for PG to be ready with the new username
until docker compose -f docker/docker-compose.dev.yml exec postgres pg_isready -U [project-name] 2>/dev/null; do sleep 1; done
pnpm db:generate   # Generate migrations from new schema
pnpm db:migrate    # Apply to local database
pnpm typecheck     # Verify everything compiles
```

Fix any errors before proceeding.

---

## Phase 3: Backlog generation

Generate structured epics, stories, and tasks. Hold these in memory for the provision step.

### Epic format
```
Epic: [E1] [Name]
Priority: P0 (MVP) | P1 (post-MVP) | P2 (future)
Stories:
  - [E1-S1] As a [persona], I want [capability], so that [value]
    Acceptance criteria:
      - [ ] [Testable criterion]
      - [ ] [Testable criterion]
    Story points: [1/2/3/5/8/13]
    Tasks:
      - [ ] [Implementation task]
      - [ ] [Implementation task]
      - [ ] Write tests for [feature]
```

### Standard epics (include in every project)
- **E0: Project setup** — Seed repo clone, env configuration, local dev working, CI green (P0, pre-done by seed — mark complete)
- **E1: Auth + user management** — Sign up, sign in, session handling, route protection (P0)
- **E-LAST: Deployment** — Production env vars, domain, SSL, monitoring, DO App Platform config (P0)

### Story point scale
1=trivial, 2=small, 3=medium-small, 5=medium, 8=large, 13=very large, 21=must split

---

## Phase 4: Provision

After scaffold and backlog are ready, present the summary:

> **[Project Name] — Scaffold Complete**
>
> **Files generated:** [count] files across [domains]
> **Database tables:** [list]
> **Auth plugins:** [list]
> **BullMQ queues:** [list]
> **Test stubs:** [count] unit, [count] integration, [count] E2E
>
> **Backlog:** [N] epics, [N] stories, [N] total story points
> **MVP scope:** [N] stories, [N] story points

**In interactive mode (default):** ask about each provision step **one at a time**, waiting for an explicit yes/no before proceeding to the next. Do NOT present them as a batch.

**In auto-accept mode:** run each step sequentially without asking. Show what you're doing (so the builder can follow along or interrupt) but don't wait for approval. If any step fails (auth error, tool unavailable, etc.), stop and report — don't skip.

Ask/run in this order:

### Pre-flight checks

Before asking about each step, verify tool availability:
```bash
gh auth status          # GitHub CLI authenticated?
doctl account get       # DigitalOcean CLI authenticated?
# Asana MCP — attempt to list workspaces via MCP tools
# Jira MCP — attempt to list projects via MCP tools
```

If a tool is not available for a given step, say so and offer to skip with manual instructions instead.

### Step 1: GitHub repository

Ask:
> **Would you like me to set up a GitHub repository?**
> I can either:
> - **Create a new repo** — tell me which org (e.g., `fractionwork`, your personal account, or another org)
> - **Use an existing empty repo** — give me the URL (e.g., `git@github.com:myorg/my-project.git`)
>
> *(Requires: `gh` CLI authenticated)*

**If creating a new repo:** Ask which org/owner to create it under. Do NOT assume `fractionwork` — ask explicitly. Then:
```bash
gh repo create [owner]/[project-name] \
  --private \
  --description "[one-liner]" \
  --source . \
  --remote origin

git add -A
git commit -m "feat: bootstrap [project-name] from devhawk-seed

Scaffold generated by DevHawk Bootstrap.

Stack: Next.js 16 · Drizzle · Better Auth · BullMQ · shadcn/ui
Infrastructure: DO App Platform · Managed PG 16 · Managed Redis 7

Epics: [N] ([N] MVP)
Story points: [N] total ([N] MVP)"

git branch -M main
git push -u origin main
```

**If using an existing repo:** Verify it's empty (no commits), then:
```bash
git remote add origin [repo-url]
git add -A
git commit -m "feat: bootstrap [project-name] from devhawk-seed

Scaffold generated by DevHawk Bootstrap.

Stack: Next.js 16 · Drizzle · Better Auth · BullMQ · shadcn/ui
Infrastructure: DO App Platform · Managed PG 16 · Managed Redis 7

Epics: [N] ([N] MVP)
Story points: [N] total ([N] MVP)"

git branch -M main
git push -u origin main
```

If the existing repo has commits, STOP and ask the user how to proceed. Do NOT force-push.

If no or `gh` unavailable: tell the user to create the repo manually and provide the git commands.

### Step 2: Project management backlog

Detect which project management MCP servers are available (Asana, Jira, or both). Then ask:

**If both Asana and Jira are connected:**
> **Where would you like me to create the project backlog?**
> - **Asana** — I'll create a project with sections and populate epics/stories
> - **Jira** — I'll create a project with a board and populate epics/stories
> - **Both** — I'll populate both
> - **Skip** — I'll save the backlog to `backlog.md`

**If only Asana is connected:**
> **Would you like me to create an Asana project and populate the backlog?**
> This will create a project with [N] epics and [N] stories in your Asana workspace.
> *(Asana MCP connected)*

**If only Jira is connected:**
> **Would you like me to create a Jira project and populate the backlog?**
> This will create a project with [N] epics and [N] stories in your Jira instance.
> *(Jira Cloud MCP connected)*

**If neither is connected:**
> **No project management MCP is connected (Asana or Jira).**
> I'll save the backlog to `backlog.md`. You can populate your PM tool later.

#### Asana backlog creation
Use the Asana MCP tools. The MCP server URL is `https://mcp.asana.com/v2/mcp`.
1. **Create project** — Name: "[Project Name]", notes include one-liner + GitHub repo link
2. **Create sections** — Backlog, Ready, In Progress, Review, Done
3. **Create tasks for each epic** in "Backlog" section
4. **Create subtasks for each story** with user story, acceptance criteria, story points
5. **Mark E0 complete**

#### Jira backlog creation
Use the Jira Cloud MCP tools.
1. **Create project** — Name: "[Project Name]", key derived from name, project type: Scrum or Kanban (ask user preference)
2. **Create epics** for each epic in the backlog
3. **Create stories** under each epic with description, acceptance criteria, and story points
4. **Mark E0 epic as Done**

#### Fallback
If the user skips or MCP is unavailable, write the backlog to `backlog.md`:
> Backlog saved to `backlog.md`. To populate later, connect an MCP server and say **"provision backlog"**.

### Step 3: Update AppSpec placeholders

Ask:
> **Would you like me to replace the `<PROJECT_NAME>` placeholder in the AppSpec files and CI workflow?**
> This substitutes `[project-name]` into `app.yaml`, `app.staging.yaml` (if kept), and `.github/workflows/ci.yml`.

If yes:
```bash
sed -i "s|<PROJECT_NAME>|[project-name]|g" app.yaml
[ -f app.staging.yaml ] && sed -i "s|<PROJECT_NAME>|[project-name]|g" app.staging.yaml
sed -i "s|<PROJECT_NAME>|[project-name]|g" .github/workflows/ci.yml
# Also update the github.repo owner if it differs from `fractionwork`
sed -i "s|fractionwork/[project-name]|[owner]/[project-name]|g" app.yaml
[ -f app.staging.yaml ] && sed -i "s|fractionwork/[project-name]|[owner]/[project-name]|g" app.staging.yaml
git add app.yaml app.staging.yaml .github/workflows/ci.yml 2>/dev/null
git commit -m "chore: update AppSpec for [project-name]"
git push
```

### Step 4: DO App Platform app

Ask:
> **Would you like me to provision the DigitalOcean App Platform app now?**
> This creates the DO Project, managed PG + Valkey clusters, both app shells (prod and, if configured, staging), triggers the first deploy, and captures the ingress URL.
> *(Requires: `doctl` CLI authenticated, DO ↔ GitHub org OAuth granted. You can skip and do it later.)*

If yes: defer the entire DigitalOcean flow to the `do-deploy` skill. It walks through DO Project creation, cluster provisioning, app creation, secret seeding, first deploy, and ingress capture in a single guided flow with the diagnostics that save time when things go wrong. Say:

> I'll hand off to the `do-deploy` skill now — it'll walk the DO provisioning end-to-end.

Then invoke the `do-deploy` skill with the project's `<PROJECT_NAME>` and `<ProductName>` values.

If no or `doctl` unavailable: tell the user to run **"deploy to DO"** later when they're ready — that triggers the `do-deploy` skill. No partial inline provisioning from this skill.

### Step 5: Report

After all steps (whether completed or skipped), give a final summary:

> **[Project Name] — Ready**
>
> **GitHub:** [link, or "create manually"]
> **Backlog:** [Asana link, Jira link, "see backlog.md", or whichever was used]
> **DO App:** [link, or "create later"]
>
> **What's ready:**
> - [List what was actually provisioned]
>
> **What to do manually:**
> - [List anything that was skipped, with instructions]
>
> **Start building:**
> ```
> pnpm dev
> ```
> Pick a story from Asana (or backlog.md) and say **"build E1-S1"**.

---

## Constraints

- NEVER evaluate or recommend technology — the stack is decided
- NEVER skip discovery — even if the user says "just scaffold it" or provides a complete spec
- NEVER assume answers to discovery questions from a provided spec — always ask explicitly
- ALWAYS flag technology conflicts between a provided spec and the DevHawk stack, and discuss before proceeding
- ALWAYS wait for checkpoint confirmation before generating code
- ALWAYS run typecheck after scaffold generation before proceeding
- ALWAYS include organizationId on tenant-scoped tables
- ALWAYS generate test stubs alongside feature code
- ALWAYS follow patterns in the docs/ directory
- In interactive mode: ALWAYS ask about each Phase 4 provision step individually — do NOT batch them
- In interactive mode: ALWAYS wait for an explicit yes/no on each provision step before proceeding
- In auto-accept mode: run all steps sequentially, show output, stop only on failure or builder interruption
- NEVER push to a repo that already has commits (safety check: verify remote is empty or non-existent)
- NEVER put secrets in shell commands, commit messages, or backlog files
