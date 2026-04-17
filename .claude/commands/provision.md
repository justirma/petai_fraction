# Provision project

Create the GitHub repository, Asana project, and optionally the DO App Platform app for this DevHawk project. Push the current code and populate the backlog.

## Pre-flight checks

Before provisioning, verify:

1. The project has been bootstrapped (CLAUDE.md has a project-specific section at the top)
2. `pnpm typecheck` passes
3. No existing git remote named `origin` (or confirm with user before overwriting)

If the project hasn't been bootstrapped yet, tell the user to run **"bootstrap"** first.

Check which tools are available:
```bash
gh auth status          # GitHub CLI
doctl account get       # DigitalOcean CLI
```
Also check if Asana MCP is connected. Report what's available, proceed with what IS available, write instructions for what isn't.

## Steps

### 1. Determine project name

Read the project-specific section at the top of CLAUDE.md. Convert to kebab-case for the repo name.

### 2. Create GitHub repo

```bash
gh repo create fractionwork/[project-name] \
  --private \
  --description "[one-liner from CLAUDE.md]" \
  --source . \
  --remote origin

git add -A
git commit -m "feat: bootstrap [project-name] from devhawk-seed"
git branch -M main
git push -u origin main
```

If `gh` not available: tell user to create repo manually on GitHub, then provide `git remote add` + `git push` commands.

### 3. Create Asana project

If Asana MCP is connected:
1. Create project (name, notes with GitHub link, board layout)
2. Create sections: Backlog, Ready, In Progress, Review, Done
3. Create epic tasks in Backlog section
4. Create story subtasks with acceptance criteria and story points
5. Mark E0 (Project setup) complete

If `backlog.md` exists, read it for the structure. If Asana MCP is not connected:
> Asana MCP not connected. Backlog is in `backlog.md`.
> To connect: `claude mcp add --transport http asana https://mcp.asana.com/v2/mcp`
> Then run `/provision` again.

### 4. Update app.yaml (and app.staging.yaml if present)

Replace the `<PROJECT_NAME>` placeholder with the project slug:
```bash
sed -i "s|<PROJECT_NAME>|[project-name]|g" app.yaml
[ -f app.staging.yaml ] && sed -i "s|<PROJECT_NAME>|[project-name]|g" app.staging.yaml
sed -i "s|<PROJECT_NAME>|[project-name]|g" .github/workflows/ci.yml
git add app.yaml app.staging.yaml .github/workflows/ci.yml 2>/dev/null
git commit -m "chore: update AppSpec for [project-name]"
git push
```

### 5. Create DO App Platform app (optional)

Ask user: *"Provision the DO App Platform app now, or wait until CI is green?"*

If confirmed: defer to the `do-deploy` skill. It runs the full DO flow — Project creation, managed PG + Valkey clusters, app creation, secret seeding, first deploy, ingress capture, and (if `app.staging.yaml` is present) the staging app on shared clusters. Say:

> Handing off to the `do-deploy` skill for DigitalOcean provisioning.

Then invoke `do-deploy`.

If the user wants to defer: tell them to run **"deploy to DO"** later — that triggers `do-deploy`. No partial inline provisioning from this command.

If `doctl` not available:
> doctl not authenticated. To install + auth later:
> `brew install doctl && doctl auth init`
> Then run **"deploy to DO"** to invoke the `do-deploy` skill.

### 6. Report

Show GitHub URL, Asana project link (or "see backlog.md"), DO app URL (or "create later"), and "Start building" instructions.
