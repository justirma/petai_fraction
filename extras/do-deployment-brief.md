# Brief: DigitalOcean App Platform deployment patterns

Self-contained brief describing target deployment patterns AND a structured procedure for adopting them on an existing project. Written to be pasted into a Claude Code session — the procedure section tells the assistant exactly how to use the rest of the document.

These patterns came out of a real first-time deploy where most of an afternoon was lost to avoidable failures. The WHY for each pattern is a specific symptom you'd otherwise hit.

---

## ⚠️ Procedure — READ THIS FIRST, do not skip

When given a non-seed project, follow these four phases **strictly in order**. Do not produce edits until Phase 0–2 are complete and the user has approved the plan.

The most common failure mode of a Claude session using this brief is jumping straight to edits without first understanding the current state. **The whole point of the procedure below is to prevent that.** If you find yourself wanting to write to a file before completing Phase 1, stop and back up.

### Phase 0 — Discover current state

You need answers to ALL of these before producing a plan. Get them from the repo, then `doctl`, then the user (in that order — only ask for things the first two can't tell you).

**From the repo (read, don't guess):**
- Is there an `app.yaml` (or `app.staging.yaml`)? What components does it declare?
- Is there a `docker/` folder with a `Dockerfile` and `Dockerfile.worker`? Or just one Dockerfile?
- Is there a worker tier? (grep for: `bullmq`, `celery`, `sidekiq`, `rq`, `worker.ts`, `worker.py`)
- Is there a migration tool? (`drizzle-kit`, `prisma migrate`, `alembic`, `knex migrate`, `flyway`)
- Is there a `.github/workflows/` deploy job? Which CLI does it call?
- What env vars does the code expect? (grep `process.env.` or `os.environ`)

**From `doctl` (only if the project is already deployed somewhere on DO):**
```bash
doctl auth list                         # which team contexts are configured
doctl account get                       # what team you're in right now
doctl apps list                         # is there a deployed app?
doctl apps spec get <app-id>            # the LIVE spec (often differs from repo's app.yaml!)
doctl databases list                    # what managed clusters exist
doctl databases firewalls list <id>     # is the cluster shared with other apps?
doctl projects list                     # what DO Projects exist
```

**From the user (only what the above can't answer):**
- "Is this project pre-launch, or does prod carry real user traffic / sensitive data?" (drives staging-on-shared-clusters safety)
- "Which DO team should we deploy into?" (if multiple in `doctl auth list`)
- "Are you migrating from another platform (Vercel, Render, Fly), or is this a greenfield DO deploy?"
- For migrations: "Where does the database live today, and can it be replaced or do we need to data-migrate?"

**If you cannot answer something, ASK. Do NOT assume.** Bad assumptions in Phase 0 produce bad plans in Phase 2 and broken deploys in Phase 3.

### Phase 1 — Compare current state to target patterns

Produce a comparison table covering all 7 target patterns (defined below). For each pattern, populate four columns:

| # | Pattern | Current state | Target state | Status | Blocker? |
|---|---|---|---|---|---|
| 1 | `databases:` binding | (what the repo / live spec actually has) | `databases:` block + `production: true` + `cluster_name` | ✅ / ⚠️ / ❌ / ⚪ N/A | (any reason this can't be done?) |
| 2 | App-level envs | … | … | … | … |
| 3 | `dockerfile_path` on jobs | … | … | … | … |
| 4 | Staging-on-shared-clusters | … | optional | … | "real users on prod" → not safe |
| 5 | Projects + env tags | … | … | … | … |
| 6 | DO ↔ GitHub org OAuth | … | granted for active team + this repo's org | … | … |
| 7 | Region-pin same metro | … | … | … | "PG in nyc3, app in fra" → migration needed |

Status legend:
- ✅ MATCHES — already correct, leave alone
- ⚠️ PARTIAL — partially right; needs adjustment
- ❌ MISSING — not done; needs to be added
- ⚪ N/A — doesn't apply (e.g. no staging env requested, or single-region forced by compliance)

**Show this table to the user BEFORE proposing any changes.** Then wait for them to react. They may scope down, deprioritize, or flag context you didn't have.

### Phase 2 — Produce a phased migration plan

For each ❌/⚠️ row, propose a fix. Group fixes into phases that don't break the running app, and split each phase into three explicit categories so they don't get conflated:

- **Provisioning** — infra changes (doctl commands, dashboard actions, cluster creation, Project assignment). These are not free or instant; some are not reversible cheaply (deleting clusters, changing regions).
- **Code updates** — file edits in the repo (path + nature of change, no diffs yet — diffs come in Phase 3).
- **Config updates** — env vars, secrets, dashboard settings. App-level vs per-component matters.

**Phase the plan to avoid downtime on prod:**
- **Phase A — Additive** — changes that don't disrupt the running app (e.g. ADD app-level envs alongside existing per-component ones; DON'T remove the old ones yet)
- **Phase B — Cutover** — the deploy that switches behavior (e.g. new app.yaml with `databases:` binding goes live, removing the SECRET DATABASE_URL)
- **Phase C — Cleanup** — remove deprecated config (per-component env duplicates, dead clusters, etc.)

If the project is **pre-launch** (no real users), you can compress A+B+C into one phase. **Be explicit about which world you're in** — you should know from Phase 0.

Format each phase like this:

```markdown
## Phase A — Additive (zero-downtime)

### Provisioning
1. Create DO Project "<ProductName>" if not present
   `doctl projects create --name <ProductName> ...`
2. Tag existing PG cluster with env:prod, product:<name>
   `doctl databases tag <id> ...`

### Code updates
1. `app.yaml` — add top-level `envs:` block with DATABASE_URL, REDIS_URL,
   BETTER_AUTH_SECRET, BETTER_AUTH_URL, NEXT_PUBLIC_APP_URL, NODE_ENV
   (do NOT remove the per-component copies yet — that's Phase C)
2. `.github/workflows/ci.yml` — no change this phase

### Config updates
1. DO Dashboard → app → Settings → App-Level Env Vars → confirm BETTER_AUTH_SECRET
   is set at app level (was per-component); leave per-component copy in place

### Validation before Phase B
- Deploy this phase: `doctl apps update <id> --spec app.yaml`
- Confirm /api/health → 200
- `doctl apps spec get <id>` → confirm app-level envs are present
- `doctl apps logs <id> --type=run` → no missing-env errors
```

### Phase 3 — Execute with per-phase checkpoints

Only after the user approves the Phase 2 plan. For each phase:

1. **Announce** — "Starting Phase A. This will: [N file edits], [N doctl commands]. Provisioning commands listed; I'll pause for confirmation before each one."
2. **Execute code + config edits** without per-file confirmation (those are reversible via git).
3. **Pause before each provisioning command** that creates, modifies, or deletes infra. Show the exact command, what it'll cost, and what it changes. Wait for the user to say go.
4. **Run validation** at the end of the phase. If anything is wrong, STOP. Do not move to the next phase until validation passes.
5. **Checkpoint** — "Phase A complete. Validation: [results]. Ready for Phase B?"

**Never batch phases.** Always pause between them. The user might want to soak Phase A in prod for a day before doing Phase B.

**Never execute destructive provisioning** (deleting clusters, dropping logical databases, changing cluster size) without explicit per-command confirmation, even if the user pre-approved the plan. The plan is intent; each destructive command is its own decision.

---

## Target patterns (the 7)

### 1. Use `databases:` block with `production: true` + `cluster_name`

Reference EXISTING standalone managed clusters rather than inline `production: false` dev databases:

```yaml
databases:
  - name: db
    engine: PG
    version: "16"
    production: true
    cluster_name: <your-existing-cluster-name>
  - name: valkey
    engine: VALKEY
    production: true
    cluster_name: <your-existing-valkey-cluster>
```

App Platform automatically:
- Injects `${db.DATABASE_URL}`, `${db.HOSTNAME}`, `${db.USERNAME}`, `${db.PASSWORD}`, `${db.PORT}`, `${db.CA_CERT}` (and `${valkey.*}` equivalents) as bindable env vars
- Uses the **private VPC hostname** at runtime
- Configures TLS using DO's signed CA cert
- Adds the app to each cluster's trusted sources (firewall) automatically

**Anti-pattern to avoid:** `type: SECRET` env vars with hardcoded `private-<host>` URLs. That bypasses the binding, so DO never injects the CA cert and the private hostname doesn't resolve from inside the container — connections hang for 31 seconds on TLS handshake before getting killed.

### 2. App-level envs, not per-component envs

Shared values (`DATABASE_URL`, `REDIS_URL`, auth secrets, URL vars) go in the top-level `envs:` block so every component — service, worker, pre-deploy job — inherits them automatically:

```yaml
envs:
  - key: DATABASE_URL
    scope: RUN_AND_BUILD_TIME
    value: ${db.DATABASE_URL}
  - key: REDIS_URL
    scope: RUN_AND_BUILD_TIME
    value: ${valkey.DATABASE_URL}
  - key: BETTER_AUTH_SECRET
    scope: RUN_TIME
    type: SECRET
```

Per-component envs are ONLY for genuinely scoped secrets (e.g. `RESEND_API_KEY` on the worker, `STRIPE_WEBHOOK_SECRET` on the service that handles the webhook).

**Anti-pattern to avoid:** declaring `DATABASE_URL` only on the service. The pre-deploy migration job won't inherit it — it'll reach `drizzle-kit migrate` (or your migration tool) and print "DATABASE_URL not found" before exiting.

### 3. Pre-deploy jobs MUST set `dockerfile_path`

If you have a pre-deploy migration job (recommended), it must specify its Dockerfile explicitly:

```yaml
jobs:
  - name: db-migrate
    github:
      repo: <owner>/<repo>
      branch: main
    dockerfile_path: docker/Dockerfile.worker   # ← critical
    kind: PRE_DEPLOY
    run_command: npx drizzle-kit migrate
```

**Anti-pattern to avoid:** omitting `dockerfile_path`. DO falls back to the Heroku Node buildpack, which runs `pnpm build` (full Next.js build) on a job that only needs to run migrations. The build fails with "Failed to collect page data for /dashboard" and a footer "Love, Heroku". The worker Dockerfile is usually the right base — it has your ORM CLI and all deps without needing a full app build.

### 4. Shared staging via dedicated PG users + db_name/db_user (optional)

For pre-launch products, staging can share prod's managed clusters to save ~$30/mo. Use the `db_name` + `db_user` fields in the `databases:` binding to isolate at the PG user level:

```yaml
# Staging databases: block (same cluster_name as prod, different db_name + db_user)
databases:
  - name: db
    engine: PG
    version: "16"
    production: true
    cluster_name: <project>-db
    db_name: <project>_staging
    db_user: <project>_staging

envs:
  - key: DATABASE_URL
    scope: RUN_AND_BUILD_TIME
    value: ${db.DATABASE_URL}    # DO composes with db_name + db_user — no manual URL needed
  - key: REDIS_URL
    scope: RUN_AND_BUILD_TIME
    value: rediss://${valkey.USERNAME}:${valkey.PASSWORD}@${valkey.HOSTNAME}:${valkey.PORT}/1
  - key: BULLMQ_PREFIX   # if you use BullMQ
    scope: RUN_TIME
    value: "bull:staging"
```

One-time setup per cluster: create the staging database + dedicated PG users + `GRANT`/`REVOKE` SQL to enforce cross-database isolation. See the seed's `docs/deployment.md` for the full runbook.

Use **defense-in-depth** on Valkey: the `/1` path is the primary isolation (full keyspace boundary via `SELECT 1` on connect), the BullMQ prefix is the backstop in case the URL ever lands without the path. Keep both.

**Skip this pattern if prod has real user traffic or sensitive data.** Shared staging means a runaway staging query can impact prod. Split staging onto its own clusters before that risk matters.

### 5. DO Projects by product, tags by environment

DO doesn't have AWS-Cost-Explorer-style reporting. The best-practice slicing is:

| Dimension | Mechanism | Examples |
|---|---|---|
| Product (primary cost center) | **Project** | `Example_1`, `Example_2` — one project per product |
| Environment | **Tag** | `env:prod`, `env:staging`, `env:dev` |
| Component role (optional) | **Tag** | `role:web`, `role:db`, `role:cache` |

The DO billing CSV (Settings → Billing → Download CSV) includes both as columns. One DO Project per **product** (not per environment). Prod and staging live in the same project, tagged differently.

### 6. DO ↔ GitHub OAuth granted per team AND per org

Per-user GitHub auth is not enough. For `doctl apps create` to succeed against a repo in a GitHub organization, **the DigitalOcean team where you're deploying** must have the org-level OAuth grant. If missing, the CLI returns a 400 with "GitHub user not authenticated."

Fix, one-time per team + org pair:
- Visit https://cloud.digitalocean.com/apps
- Click "Create App" → select GitHub source → click "Manage Access"
- Grant DigitalOcean access to the org

Also: DO Personal Access Tokens are **team-scoped**. Each builder typically has multiple tokens for multiple teams. Register them as named `doctl` contexts (`doctl auth init --context <slug>`) and switch before deploying (`doctl auth switch --context <slug>`). Always verify with `doctl account get` before creating resources.

### 7. Region-pin everything to the same metro

Put the app, PG cluster, and Valkey cluster in the same metro (e.g. `nyc3`) so they share a VPC. Latency: sub-millisecond. Cross-region adds hops and removes the private-VPC hostname advantage.

---

## Common failure modes (the symptoms)

Memorize these so you recognize them fast — and reference them by number when diagnosing in Phase 0 or Phase 3 validation.

1. **31-second hang on pre-deploy job** — SECRET env var with hardcoded `private-*` hostname → see pattern 1
2. **"Love, Heroku" footer in build failure** — missing `dockerfile_path` on pre-deploy job → see pattern 3
3. **"DATABASE_URL not found" at runtime** — env declared per-component instead of app-level → see pattern 2
4. **"GitHub user not authenticated" from `doctl apps create`** — DO ↔ GitHub OAuth not granted on the target team → see pattern 6
5. **"Maximum clusters reached"** — default cap is ~10 managed DB clusters per team. Delete unused or open a support ticket. Check `doctl databases firewalls list <id>` for empty firewalls to identify deletion candidates. Don't delete clusters in unfamiliar projects without owner approval.

---

## Reference implementation

A full reference implementation of these patterns lives in the DevHawk seed at `github.com/fractionwork/devhawk-seed` (private). If you have access, the canonical files are:

- `app.yaml` — prod AppSpec with all patterns
- `app.staging.yaml` — staging-on-shared-clusters AppSpec
- `docs/deployment.md` — full runbook including first-deploy recipe and failure modes
- `.claude/skills/do-deploy/` — guided provisioning flow (SKILL.md, runbook.md, troubleshoot.md)

If you don't have access, the patterns + procedure above are complete and self-contained — you can adopt them from this brief alone.
