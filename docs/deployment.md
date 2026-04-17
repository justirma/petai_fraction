# Deployment

## Local development

### Platform support

Works on **macOS**, **Linux**, and **Windows**.

**Windows users:** Install [Docker Desktop](https://www.docker.com/products/docker-desktop/) (which includes WSL2). Run all commands from a **WSL2 terminal** (Ubuntu recommended). This gives you a native Linux environment where all tools and scripts work identically to macOS/Linux. Do not use cmd.exe or PowerShell for development commands.

To open a WSL2 terminal: install "Ubuntu" from the Microsoft Store, or use Windows Terminal with the Ubuntu profile.

### First-time setup
```bash
# 1. Clone and install
git clone git@github.com:fractionwork/[project].git
cd [project]
pnpm install

# 2. Start backing services
docker compose -f docker/docker-compose.dev.yml up -d

# 3. Set up environment
cp .env.example .env.local
# Edit .env.local with your local values (defaults work with docker-compose)

# 4. Generate and run migrations
pnpm db:generate   # Create migration files from schema
pnpm db:migrate    # Apply migrations to database

# 5. Start dev server + worker
pnpm dev          # Terminal 1: Next.js with Turbopack
pnpm worker:dev   # Terminal 2: BullMQ worker with watch mode
```

### Daily workflow
```bash
pnpm dev                                                  # Start PG + Redis + web + worker
pnpm dev:logs                                             # Tail logs (web + worker)
pnpm dev:status                                           # Show process table
pnpm dev:stop                                             # Stop all
pnpm db:studio                                            # Browse data (optional)
```

## DO App Platform deployment

### AppSpec

The `app.yaml` file declares the entire application. Key components:

- **web** (Service): Next.js app, port 8080, health check at `/api/health`
- **job-worker** (Worker): BullMQ consumer, always-on, no HTTP
- **db-migrate** (Job, PRE_DEPLOY): runs `drizzle-kit migrate`. **Must set `dockerfile_path: docker/Dockerfile.worker`** — without it, DO falls back to the Heroku Node buildpack which tries `pnpm build` and fails. See "Common failure modes" below.
- **db** (Database binding): references the standalone `<PROJECT_NAME>-db` Managed PostgreSQL 16 cluster via `production: true` + `cluster_name`
- **valkey** (Database binding): references the standalone `<PROJECT_NAME>-valkey` Managed Valkey cluster (DO's Redis replacement) the same way

For production + staging in the same product, the staging spec lives at `app.staging.yaml` and shares the same clusters — see the "Staging environment" section below.

### Database binding patterns

**Use the `databases:` block with `production: true` + `cluster_name`** to reference *existing* standalone managed clusters. This is the only DO-idiomatic way and the only way that works reliably for App Platform deploys.

```yaml
databases:
  - name: db
    engine: PG
    version: "16"
    production: true
    cluster_name: <PROJECT_NAME>-db
  - name: valkey
    engine: VALKEY
    production: true
    cluster_name: <PROJECT_NAME>-valkey
```

When you do this, DO automatically:
- Injects `${db.DATABASE_URL}`, `${db.HOSTNAME}`, `${db.USERNAME}`, `${db.PASSWORD}`, `${db.PORT}`, `${db.CA_CERT}` (and `${valkey.*}` equivalents) as bindable env vars
- Uses the **private VPC hostname** at runtime, not the public one
- Configures TLS using DO's signed CA cert
- Adds the app to each cluster's trusted sources (firewall) automatically

Reference these in your envs block:

```yaml
envs:
  - key: DATABASE_URL
    scope: RUN_AND_BUILD_TIME
    value: ${db.DATABASE_URL}
  - key: REDIS_URL
    scope: RUN_AND_BUILD_TIME
    value: ${valkey.DATABASE_URL}
```

**Do NOT use `type: SECRET` env vars with hardcoded `private-<host>` URLs.** That bypasses the binding, so DO never injects the CA cert and the private hostname doesn't resolve from the App Platform container — connections hang for 31 seconds on TLS handshake before getting killed. See "Common failure modes" below.

**App-level envs > per-component envs** for shared values like `DATABASE_URL`, `REDIS_URL`, `BETTER_AUTH_SECRET`, `BETTER_AUTH_URL`, `NEXT_PUBLIC_APP_URL`. A single value at the top-level `envs:` block flows to web + worker + the db-migrate job. Per-component envs are for genuinely scoped secrets (e.g. `RESEND_API_KEY` only on the worker).

### First deploy

This is the canonical recipe. Replace `<PROJECT_NAME>` (kebab-case slug) and `<ProductName>` (display name for the DO Project) with your values.

```bash
# Install doctl + auth
brew install doctl
doctl auth init   # paste a personal access token
gh auth status    # confirm GitHub CLI is also authed

# IMPORTANT: authorize DO ↔ GitHub on the org level (one-time per GH org).
# Visit https://cloud.digitalocean.com/apps → Create App → GitHub source → "Manage Access"
# and grant DigitalOcean access to the relevant org. Without this,
# `doctl apps create` fails with "GitHub user not authenticated".

# 1. Create the DO Project (product-level grouping for cost attribution).
PROJECT_ID=$(doctl projects create --name <ProductName> \
  --description "<ProductName> production + staging" \
  --purpose "Web Application" --environment Production \
  --format ID --no-header)

# 2. Create the standalone managed clusters (region-pinned, tagged).
doctl databases create <PROJECT_NAME>-db \
  --engine pg --version 16 --size db-s-1vcpu-1gb --region nyc3 --num-nodes 1 \
  --tag "env:prod,product:<PROJECT_NAME>"
doctl databases create <PROJECT_NAME>-valkey \
  --engine valkey --size db-s-1vcpu-1gb --region nyc3 --num-nodes 1 \
  --tag "env:prod,product:<PROJECT_NAME>"
# Wait until both report Status: online (1–5 min).

# 3. Create the dedicated prod PG user (staging user created later if needed).
PG_ID=$(doctl databases list --format ID,Name --no-header | awk '$2=="<PROJECT_NAME>-db"{print $1}')
doctl databases user create "$PG_ID" <PROJECT_NAME>_prod

# 4. Temporarily add your IP for psql access, run GRANT SQL, then remove.
MY_IP=$(curl -s ifconfig.me)
doctl databases firewalls append "$PG_ID" --rule "ip_addr:$MY_IP"
PGURI=$(doctl databases connection "$PG_ID" --format URI --no-header)
# Connect as doadmin to defaultdb and grant the prod user full access:
psql "$PGURI" <<'SQL'
GRANT CONNECT ON DATABASE defaultdb TO <PROJECT_NAME>_prod;
GRANT CREATE ON DATABASE defaultdb TO <PROJECT_NAME>_prod;
GRANT ALL PRIVILEGES ON SCHEMA public TO <PROJECT_NAME>_prod;
GRANT ALL ON ALL TABLES IN SCHEMA public TO <PROJECT_NAME>_prod;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO <PROJECT_NAME>_prod;
ALTER DEFAULT PRIVILEGES FOR ROLE doadmin IN SCHEMA public
  GRANT ALL ON TABLES TO <PROJECT_NAME>_prod;
ALTER DEFAULT PRIVILEGES FOR ROLE doadmin IN SCHEMA public
  GRANT ALL ON SEQUENCES TO <PROJECT_NAME>_prod;

-- drizzle-kit migration tracking schema. CREATE ON DATABASE above lets the
-- app user create it on first run. If upgrading from doadmin-run migrations,
-- the drizzle schema already exists and needs explicit grants:
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = 'drizzle') THEN
    EXECUTE 'GRANT ALL PRIVILEGES ON SCHEMA drizzle TO <PROJECT_NAME>_prod';
    EXECUTE 'GRANT ALL ON ALL TABLES IN SCHEMA drizzle TO <PROJECT_NAME>_prod';
  END IF;
END $$;
SQL
# Remove your IP from trusted sources (find UUID, then remove)
FW_UUID=$(doctl databases firewalls list "$PG_ID" --format UUID,Type,Value --no-header | grep "$MY_IP" | awk '{print $1}')
doctl databases firewalls remove "$PG_ID" --uuid "$FW_UUID"

# 5. Create the app. DO auto-binds the clusters declared in app.yaml's
#    databases: block (with db_name + db_user) and auto-adds the app to
#    each cluster's trusted sources.
doctl apps create --spec app.yaml
APP_ID=$(doctl apps list --format ID,Spec.Name --no-header | awk '$2=="<PROJECT_NAME>"{print $1}')

# 6. Assign every resource to the <ProductName> project (for cost reporting).
VALKEY_ID=$(doctl databases list --format ID,Name --no-header | awk '$2=="<PROJECT_NAME>-valkey"{print $1}')
doctl projects resources assign "$PROJECT_ID" \
  --resource="do:app:$APP_ID" \
  --resource="do:dbaas:$PG_ID" \
  --resource="do:dbaas:$VALKEY_ID"

# 7. Set the one secret the binding can't supply: BETTER_AUTH_SECRET.
#    Easiest path: DO dashboard → Apps → <PROJECT_NAME> → Settings → App-Level Env Vars,
#    paste the value, mark it Encrypted. Generate with: openssl rand -hex 32

# 8. Trigger the first deploy. The pre-deploy db-migrate job runs Drizzle migrations.
doctl apps create-deployment "$APP_ID"

# 9. Once ACTIVE, capture the assigned ingress and set the URL env vars.
INGRESS=$(doctl apps get "$APP_ID" -o json | jq -r '.[0].default_ingress')
# In dashboard, set BETTER_AUTH_URL and NEXT_PUBLIC_APP_URL to $INGRESS, then redeploy.

# 10. Smoke-test.
curl -f "$INGRESS/api/health"   # expect 200

# 11. Bootstrap the first superadmin.
#     First, sign up via the app's /sign-up page. Then run:
curl -X POST "$INGRESS/api/bootstrap" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $(doctl apps spec get $APP_ID -o json | jq -r '.envs[] | select(.key=="SUPERADMIN_SETUP_TOKEN") | .value')" \
  -d '{"email":"admin@example.com","orgName":"<ProductName>","orgSlug":"<PROJECT_NAME>"}'
#     Returns 200 on first use, 409 on subsequent calls (self-disabling).
#     SUPERADMIN_SETUP_TOKEN must be set in DO dashboard env vars first.
```

### DO Projects + tags for cost attribution

DO does not provide AWS-Cost-Explorer-style reporting. Best-practice for slicing the bill:

| Dimension | Mechanism | Example values |
|---|---|---|
| Product (primary cost center) | **Project** | `<ProductName>` (one per product) |
| Environment | **Tag** | `env:prod`, `env:staging`, `env:dev` |
| Component role (optional) | **Tag** | `role:web`, `role:db`, `role:cache` |

The DO billing CSV (Settings → Billing → Download CSV next to each invoice) includes both project and tags as columns. Pivot to answer "what is `<ProductName>` costing me" or "what is staging costing me across all products."

### Subsequent deploys

Handled automatically:
1. Push to `develop` or `main` → GitHub Actions runs quality + test gates
2. If both pass and branch is `main` → Docker images built and pushed to GHCR (tagged with commit SHA) → prod deploy
3. If both pass and branch is `develop` → images tagged `:develop-<sha>` and pushed → staging deploy
4. DO App Platform detects new image → runs pre-deploy Job (migrations) → deploys new containers

Feature workflow: branch from `develop` → PR to `develop` → merge to `develop` (CI + staging deploy) → when ready for release, merge `develop` to `main` (triggers prod deploy).

### Manual rollback
```bash
# List recent deployments
doctl apps list-deployments <app-id>

# Rollback to a specific deployment (up to 10 revisions kept)
doctl apps create-deployment <app-id> --force-rebuild
```

Or in the DO dashboard: Apps → your app → Activity → click any previous deployment → Rollback.

## Docker images

### Service image (docker/Dockerfile)
Multi-stage build: deps → build → production. Uses `output: "standalone"` for minimal image size (~150-200MB). The `SKIP_ENV_VALIDATION=1` flag during build prevents env var checks at compile time.

### Worker image (docker/Dockerfile.worker)
Simpler: deps → production. Runs `tsx lib/jobs/worker.ts` directly. Shares the same codebase — just a different entry point. Also used by the `db-migrate` pre-deploy job so drizzle-kit is available.

### Building locally
```bash
docker build -f docker/Dockerfile -t <PROJECT_NAME>-web .
docker build -f docker/Dockerfile.worker -t <PROJECT_NAME>-worker .
```

## Environment variables

### Where they live
- **Local**: `.env.local` (git-ignored)
- **CI**: GitHub repository secrets + workflow env block
- **Production**: DO App Platform app-level envs (set in dashboard or AppSpec); database vars auto-injected by bindings

### Secret management
- Secrets (API keys, auth secret) use `type: SECRET` in AppSpec — encrypted at rest, not visible in logs
- Database URLs are injected by the `databases:` binding — never hardcoded
- Never commit `.env.local` or any file containing real credentials

### Required secrets per environment
| Variable | Local | CI | Production |
|----------|-------|----|------------|
| DATABASE_URL | docker-compose PG | GitHub service | `${db.DATABASE_URL}` (auto) |
| REDIS_URL | docker-compose Redis | GitHub service | `${valkey.DATABASE_URL}` (auto) |
| BETTER_AUTH_SECRET | any 32+ char string | test string | generate with `openssl rand -hex 32` |
| BETTER_AUTH_URL | http://localhost:3000 | http://localhost:3000 | captured ingress after first deploy |
| NEXT_PUBLIC_APP_URL | http://localhost:3000 | http://localhost:3000 | captured ingress after first deploy |

## CI/CD pipeline

Defined in `.github/workflows/ci.yml`. Stages:

1. **Quality gate** (~1 min): lint, typecheck, security audit
2. **Test gate** (~2.5 min): Vitest (with PG + Redis services), Playwright E2E
3. **Deploy prod** (~3 min, `main` push only): Docker build → GHCR push → DO deploy (prod)
4. **Deploy staging** (~3 min, `develop` push only): Docker build with `:develop-<sha>` tag → GHCR push → DO deploy (staging)

Both quality and test run in parallel. Deploy jobs only run if both pass. Staging and prod deploys are mutually exclusive per push (they key off `github.ref`).

## Staging environment

Staging tracks the `develop` branch, lives in the same DO Project as prod, and is declared in `app.staging.yaml`. To minimize cost, staging **shares the prod Managed Postgres cluster and Managed Valkey instance** with these isolation mechanisms:

| Resource | Prod | Staging |
|---|---|---|
| Postgres database | `defaultdb` via `<PROJECT_NAME>_prod` user | `<PROJECT_NAME>_staging` DB via `<PROJECT_NAME>_staging` user |
| Valkey logical DB | `0` (default) | `1` (via URL path `/1`) |
| BullMQ key prefix | `bull` (default) | `bull:staging` (via `BULLMQ_PREFIX` env) |
| Better Auth secret | prod value | **generated fresh** — never reuse |
| Domain | prod domain | `*.ondigitalocean.app` subdomain assigned by DO |

Both apps reference the same standalone clusters via `databases:` block + `production: true` + `cluster_name`. DO automatically adds both apps to each cluster's trusted sources.

**Why both the Valkey DB number AND a BullMQ prefix?** Intentional defense-in-depth. `ioredis` parses the `/1` path and issues `SELECT 1` on connect, so `FLUSHDB`, `KEYS`, and `MONITOR` all respect the DB boundary — that alone is strong isolation. The `bull:staging` prefix is the backstop: if `REDIS_URL` ever lands without the `/1` path (config drift, a misapplied secret, manual override via dashboard), BullMQ keys still land in `bull:staging:*` rather than prod's `bull:*`. It also future-proofs a move to Valkey Cluster mode, where `SELECT` isn't available. Removing either layer weakens this — keep both.

### Accepted risk

Sharing the PG cluster and Valkey means staging and prod share CPU, memory, connection pool, maintenance windows, and backup schedule. A runaway staging query or filled cache can impact prod. Split staging onto its own managed resources before prod carries real user traffic or sensitive data — see "Splitting staging off later" below.

### Branching & deploy flow

1. Feature branches PR into `develop`
2. Merge to `develop` → GitHub Actions runs `quality` + `test` gates → `deploy-staging` job builds + pushes GHCR images and calls `digitalocean/app_action/deploy@v2` against `<PROJECT_NAME>-staging`
3. When ready for production, merge `develop` → `main` → prod deploy job runs

The staging AppSpec sets `deploy_on_push: false` so raw pushes to `develop` do **not** bypass CI — only the GHA job can trigger a staging deploy.

### PG user isolation (db_name + db_user)

Both apps share the same PG cluster but use **dedicated database users** with `GRANT`/`REVOKE` isolation. The `db_name` and `db_user` fields in the AppSpec `databases:` block tell DO to compose `${db.DATABASE_URL}` with the right user and database — no manual URL composition needed.

```yaml
# Prod app.yaml — connects as <PROJECT_NAME>_prod to defaultdb
databases:
  - name: db
    engine: PG
    version: "16"
    production: true
    cluster_name: <PROJECT_NAME>-db
    db_name: defaultdb
    db_user: <PROJECT_NAME>_prod

# Staging app.staging.yaml — connects as <PROJECT_NAME>_staging to <PROJECT_NAME>_staging
databases:
  - name: db
    engine: PG
    version: "16"
    production: true
    cluster_name: <PROJECT_NAME>-db
    db_name: <PROJECT_NAME>_staging
    db_user: <PROJECT_NAME>_staging
```

Both apps use the simple `${db.DATABASE_URL}` binding — DO fills in the right user, password, host, port, database, and TLS params.

The GRANT/REVOKE SQL that enforces isolation is a **one-time setup** run during the first deploy. See the "First deploy" and "Staging bootstrap" runbooks below.

### First-time staging bootstrap (runbook)

Assumes prod is deployed and `doctl auth init` is configured.

```bash
# 1. Create the staging logical database on the shared PG cluster.
PG_ID=$(doctl databases list --format ID,Name --no-header | awk '$2=="<PROJECT_NAME>-db"{print $1}')
doctl databases db create "$PG_ID" <PROJECT_NAME>_staging

# 2. Create the dedicated staging PG user + GRANT/REVOKE isolation.
doctl databases user create "$PG_ID" <PROJECT_NAME>_staging

# Temporarily add your IP for psql access.
MY_IP=$(curl -s ifconfig.me)
doctl databases firewalls append "$PG_ID" --rule "ip_addr:$MY_IP"
PGURI=$(doctl databases connection "$PG_ID" --format URI --no-header)

# Connect as doadmin to the STAGING database and grant the staging user:
psql "${PGURI/defaultdb/<PROJECT_NAME>_staging}" <<'SQL'
-- Lock prod user out of staging
REVOKE ALL ON DATABASE <PROJECT_NAME>_staging FROM <PROJECT_NAME>_prod;

-- Grant staging user full access
GRANT CONNECT ON DATABASE <PROJECT_NAME>_staging TO <PROJECT_NAME>_staging;
GRANT CREATE ON DATABASE <PROJECT_NAME>_staging TO <PROJECT_NAME>_staging;
GRANT ALL PRIVILEGES ON SCHEMA public TO <PROJECT_NAME>_staging;
GRANT ALL ON ALL TABLES IN SCHEMA public TO <PROJECT_NAME>_staging;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO <PROJECT_NAME>_staging;
ALTER DEFAULT PRIVILEGES FOR ROLE doadmin IN SCHEMA public
  GRANT ALL ON TABLES TO <PROJECT_NAME>_staging;
ALTER DEFAULT PRIVILEGES FOR ROLE doadmin IN SCHEMA public
  GRANT ALL ON SEQUENCES TO <PROJECT_NAME>_staging;

-- drizzle-kit migration tracking schema (same pattern as prod)
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = 'drizzle') THEN
    EXECUTE 'GRANT ALL PRIVILEGES ON SCHEMA drizzle TO <PROJECT_NAME>_staging';
    EXECUTE 'GRANT ALL ON ALL TABLES IN SCHEMA drizzle TO <PROJECT_NAME>_staging';
  END IF;
END $$;
SQL

# Connect as doadmin to the PROD database and lock staging user out:
psql "$PGURI" <<'SQL'
REVOKE ALL ON DATABASE defaultdb FROM <PROJECT_NAME>_staging;
SQL

# Remove your IP from trusted sources.
FW_UUID=$(doctl databases firewalls list "$PG_ID" --format UUID,Type,Value --no-header | grep "$MY_IP" | awk '{print $1}')
doctl databases firewalls remove "$PG_ID" --uuid "$FW_UUID"

# 3. Create the staging app. DO auto-binds to <PROJECT_NAME>-db + <PROJECT_NAME>-valkey
#    (referenced in app.staging.yaml's databases: block with db_name + db_user)
#    and adds the app to each cluster's trusted sources.
doctl apps create --spec app.staging.yaml
STAGING_APP_ID=$(doctl apps list --format ID,Spec.Name --no-header | awk '$2=="<PROJECT_NAME>-staging"{print $1}')

# 4. Set the one secret the binding can't supply: BETTER_AUTH_SECRET (fresh, not prod's).
#    Dashboard → Apps → <PROJECT_NAME>-staging → Settings → App-Level Env Vars.
#    Generate: openssl rand -hex 32

# 5. Trigger first deploy. db-migrate connects as <PROJECT_NAME>_staging user and
#    creates the schema in the <PROJECT_NAME>_staging database.
doctl apps create-deployment "$STAGING_APP_ID"

# 6. Capture the assigned ingress, set BETTER_AUTH_URL + NEXT_PUBLIC_APP_URL, redeploy.
doctl apps get "$STAGING_APP_ID" -o json | jq -r '.[0].default_ingress'

# 7. Assign to the <ProductName> DO project + tag env:staging.
PROJECT_ID=$(doctl projects list --format ID,Name --no-header | awk '$2=="<ProductName>"{print $1}')
doctl projects resources assign "$PROJECT_ID" --resource="do:app:$STAGING_APP_ID"
```

No manual trusted-source firewall edits for the apps — DO's binding handles it. The temporary IP firewall rule is only needed for the psql GRANT/REVOKE step and must be removed immediately after.

### Seeding staging data

After the first successful deploy:

```bash
# Locally, pointing at the staging DB:
DATABASE_URL='postgresql://doadmin:<pw>@<PROJECT_NAME>-db-...:25060/<PROJECT_NAME>_staging?sslmode=require' pnpm db:seed
```

Never copy prod data into staging — it may contain sensitive or regulated information depending on the product.

### Staging access

Staging is reachable at the DO-assigned `*.ondigitalocean.app` subdomain. Better Auth (and org membership, if multi-tenant) gates everything, identical to prod. To grant someone access, invite them via the app's normal sign-up / invite flow.

### Splitting staging off later

When prod starts carrying real traffic and the shared-resource risk no longer makes sense:

1. Provision standalone staging clusters: `doctl databases create <PROJECT_NAME>-staging-db ...` and `<PROJECT_NAME>-staging-valkey`
2. In `app.staging.yaml`, change the `databases:` block's `cluster_name` to point at the new clusters. Remove `db_name` and `db_user` (the staging cluster only has one database)
3. Drop the `<PROJECT_NAME>_staging` logical DB and user from prod's cluster: `doctl databases db delete <prod-pg-id> <PROJECT_NAME>_staging` and `doctl databases user delete <prod-pg-id> <PROJECT_NAME>_staging`
4. Drop the `BULLMQ_PREFIX` override (default `bull` is safe with a physically separate Valkey)

## Common failure modes

These are the failure modes to recognize and the fix for each. Source: lessons paid for during a real first-time DO deploy.

### Symptom: `db-migrate` job fails after ~31 seconds with no migration output

The drizzle-kit spinner runs for 31 seconds, then "component terminated with non-zero exit code: 1" with no SQL ever executing.

**Cause:** `DATABASE_URL` was set as a `type: SECRET` env var pointing at the **private** hostname (`private-<PROJECT_NAME>-db-...`). Without the `databases:` binding, DO never injects the CA cert and the private hostname does not resolve from inside the App Platform container.

**Fix:** Use the `databases:` block with `production: true` + `cluster_name` and reference `${db.DATABASE_URL}` in your envs. See "Database binding patterns" above.

### Symptom: `db-migrate` build fails with "Failed to collect page data for /dashboard"

Build logs show "ELIFECYCLE Command failed with exit code 1" and a footer "Love, Heroku".

**Cause:** The `db-migrate` job has no `dockerfile_path`, so DO defaults to the Heroku Node buildpack which tries to run `pnpm build` (Next.js) on a job that should just run a migration command.

**Fix:** Add `dockerfile_path: docker/Dockerfile.worker` to the db-migrate job. The worker Dockerfile installs all deps (including drizzle-kit) and is the right base for migration commands.

### Symptom: db-migrate runs `npx drizzle-kit migrate` and prints "DATABASE_URL not found"

The job reaches drizzle-kit but exits immediately with the missing-env error.

**Cause:** `DATABASE_URL` was declared per-component (e.g. only on `web`) instead of at the app level. The dashboard value the user pasted only attached to the web component; the db-migrate job's copy was empty.

**Fix:** Move shared env vars (DATABASE_URL, REDIS_URL, BETTER_AUTH_SECRET, BETTER_AUTH_URL, NEXT_PUBLIC_APP_URL, NODE_ENV) to the top-level `envs:` block. They flow to every component automatically.

### Symptom: `doctl apps create` fails with "GitHub user not authenticated"

The CLI returns a 400 from the DO API on first app creation against a new GitHub org.

**Cause:** DO ↔ GitHub OAuth has not been authorized for the GitHub organization (separate from per-user authorization).

**Fix:** Visit https://cloud.digitalocean.com/apps → Create App → GitHub source → "Manage Access" → grant access to the org. One-time per org. Then retry `doctl apps create`.

### Symptom: `doctl databases create` fails with "maximum clusters reached"

Account is at the default ~10 managed-DB cluster cap.

**Fix:** Either delete unused clusters (check `doctl databases firewalls list <id>` for empty firewalls + `doctl databases get <id>` for last activity to identify candidates) or open a DO support ticket to raise the limit. Don't delete clusters in unfamiliar projects without owner approval — a project named "Sunset Resources" can mean "resources to be sunset", and what looks abandoned may still be in service.

## Monitoring

- **DO dashboard**: CPU, memory, bandwidth, request count per component
- **App logs**: `doctl apps logs <app-id> --type=run` or dashboard Activity tab
- **Sentry**: Error tracking (configure DSN in env vars when ready)
- **PostHog**: Product analytics (add script to root layout when ready)
