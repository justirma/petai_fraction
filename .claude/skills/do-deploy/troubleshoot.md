# do-deploy — failure modes and fixes

Five symptoms account for almost every stuck deploy. Match the symptom, apply the fix, redeploy.

## 31-second hang on db-migrate

**Symptom:** drizzle-kit spinner runs for ~31 seconds with no SQL output, then the pre-deploy job exits with "component terminated with non-zero exit code: 1". No migrations execute. Build logs show the spinner, runtime logs show nothing useful.

**Cause:** `DATABASE_URL` was declared as a `type: SECRET` env var with a hardcoded `private-<host>` URL. That bypasses DO's binding, so:
- The CA cert is never injected
- The private hostname doesn't resolve from inside the App Platform container
- The TLS handshake hangs until App Platform's 31-second connection timeout kills it

**Fix:** Use the `databases:` block with `production: true` + `cluster_name`, and reference `${db.DATABASE_URL}` in your envs instead:

```yaml
envs:
  - key: DATABASE_URL
    scope: RUN_AND_BUILD_TIME
    value: ${db.DATABASE_URL}   # not a SECRET — this is a variable reference

databases:
  - name: db
    engine: PG
    version: "16"
    production: true
    cluster_name: <PROJECT_NAME>-db
```

**Confirm the fix:** `doctl apps spec get <app-id>` should show `DATABASE_URL` at the app level with no hardcoded `value:` pointing at `private-...`. The live spec should use the `${db.DATABASE_URL}` reference.

## Heroku buildpack failure on db-migrate

**Symptom:** Build fails on the `db-migrate` job with "Failed to collect page data for /dashboard", "ELIFECYCLE Command failed with exit code 1", and a trailing footer "Love, Heroku". The job never reaches the `run_command`.

**Cause:** The `db-migrate` job has no `dockerfile_path`. DO falls back to the Heroku Node buildpack, which runs `pnpm build` on every Node project by default. Next.js build tries to collect page data for static routes and crashes — because `db-migrate` doesn't need a Next.js build, but Heroku's buildpack doesn't know that.

**Fix:** Add `dockerfile_path: docker/Dockerfile.worker` to the db-migrate job:

```yaml
jobs:
  - name: db-migrate
    github:
      repo: fractionwork/<PROJECT_NAME>
      branch: main
    dockerfile_path: docker/Dockerfile.worker   # ← this
    kind: PRE_DEPLOY
    run_command: npx drizzle-kit migrate
    instance_size_slug: basic-xxs
```

The worker Dockerfile installs all deps (including drizzle-kit) and is the right base for migration commands — no Next.js build involved.

## DATABASE_URL not found at runtime

**Symptom:** `db-migrate` reaches `npx drizzle-kit migrate`, prints "DATABASE_URL not found" (from `drizzle.config.ts`), and exits.

**Cause:** `DATABASE_URL` was declared per-component (e.g. only on `web`) instead of at the app level. The dashboard value only attached to the web component; the db-migrate job's env was empty.

**Fix:** Move shared env vars to the top-level `envs:` block in `app.yaml` so every component inherits them:

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
  - key: BETTER_AUTH_URL
    scope: RUN_TIME
  - key: NEXT_PUBLIC_APP_URL
    scope: RUN_AND_BUILD_TIME
```

Per-component envs are only for genuinely scoped secrets (e.g. `RESEND_API_KEY` on the worker).

## GitHub user not authenticated

**Symptom:** `doctl apps create --spec app.yaml` fails with HTTP 400 and "GitHub user not authenticated" (or similar) from the DO API. The user is definitely authed with `gh` locally, and `doctl auth init` completed successfully.

**Cause:** DO ↔ GitHub OAuth has not been granted at the **organization** level. Personal authorization is not enough — DO needs an explicit org grant to read the repo.

**Fix:** One-time per GitHub org:

1. Visit https://cloud.digitalocean.com/apps
2. Click "Create App" (you won't finish — just need the flow)
3. Select "GitHub" as the source
4. Click "Manage Access"
5. Find the org in the list and grant DigitalOcean access

Then retry `doctl apps create`. No changes needed on your end.

## Maximum clusters reached

**Symptom:** `doctl databases create` fails with HTTP 412 "maximum clusters reached". Account is at the default cap (~10 managed-DB clusters).

**Fix:** Either delete unused clusters (carefully) or request a limit increase.

To identify deletion candidates:

```bash
doctl databases list --format ID,Name,Engine,Size,Status

# Clusters with empty firewall rules almost always have no live consumers
for id in $(doctl databases list --format ID --no-header); do
  NAME=$(doctl databases get "$id" --format Name --no-header)
  FW=$(doctl databases firewalls list "$id" --format UUID --no-header | wc -l)
  echo "$id  $NAME  firewall_entries=$FW"
done
```

**DO NOT** delete clusters in unfamiliar projects without explicit owner approval. A project name like "Sunset Resources" can mean "resources to be sunset" (a graveyard) but it might also hold live data for a slow-moving product. When in doubt, ask — and prefer opening a DO support ticket for a limit increase over guessing wrong.

```bash
# Support ticket route (slower but safer)
# https://cloud.digitalocean.com/support/tickets/new
# Request: raise managed database cluster limit from 10 to 20 (or your target)
```

---

*Patterns confirmed during an Example_1 prod bring-up, 2026-04.*
