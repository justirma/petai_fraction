# extras

Artifacts meant to be shared **outside** this repo — briefs, prompts, and runbooks designed to inform other projects or teams about patterns we've adopted here.

Unlike `docs/`, which targets contributors working inside this repo, everything in `extras/` is written to **stand alone**. Files here can be copy-pasted or referenced into another project's Claude Code session — including projects that were never bootstrapped from this seed.

## What's here

| File | Purpose |
|---|---|
| `do-deployment-brief.md` | DigitalOcean App Platform deployment patterns and the failure modes they prevent. Paste into a non-seed project to audit or retrofit its AppSpec. |

## How to use

This seed repo is private, so a non-seed project's Claude session **cannot fetch these files directly**. Copy the brief's contents into the prompt inline. Each prompt below tells you where to paste.

---

## Prompts

### 1. Audit a non-seed project against our DO patterns

Use this when you want to understand where an existing project differs from our patterns before changing anything. Claude produces a gap report; nothing gets modified yet.

Paste into a Claude Code session in the target project's directory:

```
Here is a deployment brief describing DigitalOcean App Platform patterns
we've adopted across our projects. Read it end-to-end, then audit this
project's AppSpec (app.yaml / app.staging.yaml if present), CI/CD workflow,
and deployment docs against the 8-item checklist at the bottom of the brief.

Produce a gap report: for each checklist item, say whether it's ✅ present,
❌ missing, or ⚠️ partial — and for each gap, explain what the impact would be
if left unchanged. Do NOT modify any files. Wait for my direction on which
gaps to close.

[paste full contents of extras/do-deployment-brief.md here]
```

### 2. Retrofit a non-seed project with our DO patterns

Use this when you've already decided to adopt the patterns and want Claude to make the edits. Pairs well with running the audit prompt first.

```
Here is a deployment brief describing DigitalOcean App Platform patterns
we've adopted across our projects. Read it end-to-end, then update this
project's AppSpec files and CI/CD workflow to match. Specifically:

1. Rewrite app.yaml around the `databases:` block pattern (pattern 1)
2. Move shared env vars to app-level (pattern 2)
3. Add `dockerfile_path` to any pre-deploy jobs (pattern 3)
4. If the project has staging, align it with pattern 4
5. Update docs/deployment.md (or equivalent) with the first-deploy recipe
   and the 5 failure modes from the brief

Do not make infrastructure changes (no doctl commands). Only edit repo files.
Summarize each change as you go. Stop and ask if anything is ambiguous.

[paste full contents of extras/do-deployment-brief.md here]
```

### 3. Diagnose a stuck DO deploy against the brief's failure modes

Use this when a DO deploy is failing and you want fast triage against the five known failure modes.

```
Our DigitalOcean App Platform deploy is failing. Here is a brief describing
5 common failure modes we've seen and the fix for each. Read the brief, then
ask me for:

- The failing deploy's build + run logs
- Our current app.yaml (and app.staging.yaml if it exists)
- The `doctl apps spec get <app-id>` output if available

Match the symptom to one of the 5 failure modes in the brief and propose the
fix. If it doesn't match any of them, say so explicitly — don't force-fit.

[paste full contents of extras/do-deployment-brief.md here]
```

---

## Adding new artifacts to `extras/`

The folder is for documents that need to travel outside this repo. If a doc belongs inside this repo for contributors, put it in `docs/` instead. Rule of thumb: if the reader might not know this codebase exists, it belongs in `extras/`.

When you add a new file, update the table above and (if applicable) add a prompt showing how to use it with a non-seed project.
