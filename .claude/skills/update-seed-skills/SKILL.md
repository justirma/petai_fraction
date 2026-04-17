---
name: update-seed-skills
description: >
  Pull the latest Claude tooling from the DevHawk seed repo into the current
  project — skills, subagents, MCP server config, and enabled plugin settings.
  Adds new items, updates existing ones, and preserves any project-added items
  not in the seed. Touches only .claude/skills/, .claude/agents/, .mcp.json,
  and the enabledPlugins/extraKnownMarketplaces keys of .claude/settings.json
  — nothing else (permissions, hooks, project-added MCP servers, and
  project-added agents are all preserved). Triggers on phrases like "update
  seed skills", "sync skills", "sync from seed", "refresh from seed",
  "pull latest tooling", "update mcp from seed", "update plugins from seed",
  "update-seed-skills".
seed_managed: true
---

# Update Seed Tooling

You sync project Claude tooling from the DevHawk seed repo. This skill runs the
bundled `scripts/sync-skills.sh` script, which fetches the seed from GitHub and
merges four categories of artifacts into the project: skills, agents, MCP
servers, and enabled plugins.

The script name (`sync-skills.sh`) is historical — its scope expanded but the
filename stayed the same to preserve muscle memory and downstream invocations.

## What this skill does (and doesn't)

**Does:**
- Fetches `fractionwork/devhawk-seed@main` via the `gh` CLI (the seed repo is private — `gh auth login` must already be done)
- Adds any **skill** (`.claude/skills/<name>/`) from the seed the project doesn't have; updates skills that differ
- Adds any **subagent** (`.claude/agents/<name>.md`) from the seed; updates agents that differ
- Merges seed `mcpServers` entries into the project's **`.mcp.json`** by name (seed wins on same-name collisions; project-added MCP servers preserved)
- Surgically merges seed `enabledPlugins` and `extraKnownMarketplaces` into the project's **`.claude/settings.json`** (seed wins on same-key collisions; project's `permissions`, `hooks`, and any other keys are NEVER touched)
- Backs up everything it overwrites to `.claude/skills/.backup/<timestamp>/`
- Skips any item whose project copy has `seed_managed: false` in its frontmatter

**Does NOT:**
- Touch `docs/`, `CLAUDE.md`, app config, env files, or any other file outside the four target paths
- Replace `.claude/settings.json` entirely (only the two plugin-related keys are merged — your hooks and permissions are safe)
- Replace `.mcp.json` entirely (project-added MCP servers are preserved)
- Delete project-added skills, agents, MCP servers, or plugins
- Prompt for confirmation per-item — it's overwrite-by-default

For the broader update that includes docs/hooks/infra, use the existing
`scripts/update-from-seed.sh` instead.

## Steps

1. **Verify location.** Confirm the current working directory is a project root
   (has `.claude/` or `CLAUDE.md`). If not, ask the user where to run.

2. **Dry run first.** Run:
   ```
   bash scripts/sync-skills.sh --dry-run
   ```
   If the project doesn't have the script yet (fresh clone, older seed) — the
   seed is private, so use `gh` to fetch the script itself:
   ```
   bash <(gh api repos/fractionwork/devhawk-seed/contents/scripts/sync-skills.sh?ref=main --jq '.content | @base64d') --dry-run
   ```
   Requires `gh auth login` beforehand.

3. **Show the plan.** Present the dry-run output to the user as a categorized
   summary:
   ```
   Sync plan:
     skills:
       + cost-estimate   (new)
       ✎ bootstrap       (update)
       — feature-build   (unchanged)
       ⊘ my-override     (seed_managed: false — preserved)
       · my-custom-skill (project-only — preserved)
     agents:
       + code-reviewer   (new)
     mcp.json:
       ✎ would merge: context7  (project's my-mcp preserved)
     settings:
       ✎ would enable: code-review@claude-plugins-official  (hooks/permissions untouched)
   ```

4. **Run the sync.** Unless the user explicitly asks to stop, run the real sync
   (no `--dry-run`). The script overwrites without per-item confirmation — that
   was the design choice.

5. **Report.** Summarize what changed:
   - Per-category counts (skills/agents added/updated; MCP merged; settings merged)
   - Location of backups (`.claude/skills/.backup/<timestamp>/`)
   - Remind the user to **restart Claude Code** for the harness to pick up new
     skills, agents, MCP servers, and plugins (these are loaded at session start).
   - Suggest committing: `git add .claude/ .mcp.json && git commit -m "chore: sync claude tooling from devhawk-seed"`

## Options

- `--only <name>...` — sync only specific skills/agents by name (matches name without the .md extension for agents)
- `--source <path>` — use a local seed clone instead of fetching from GitHub (useful when iterating on the seed itself)
- `--dry-run` — preview without writing
- `--skip-mcp` — skip the .mcp.json merge
- `--skip-settings` — skip the .claude/settings.json merge

`jq` is required for the `.mcp.json` and `.claude/settings.json` merges. If the
project's environment lacks `jq`, the script tells you and you can pass
`--skip-mcp --skip-settings` to do a skills+agents-only sync.

## When something should NOT be synced

If the project has modified a seed skill or agent locally and wants to keep
those changes, add to its frontmatter:

```yaml
---
name: bootstrap
description: ...
seed_managed: false
---
```

The sync script will skip it on subsequent runs. Remove the flag (or delete the
project copy) to re-enable syncing.

For `.mcp.json` and `.claude/settings.json`, isolation works the other way:
the script ONLY touches the keys/entries the seed declares. Anything else in
those files is preserved automatically — no opt-out flag needed.

## Important guidelines

- **Always use the bundled script.** Don't reimplement the sync logic inline
  with Read/Write calls. The script has safety rails (backup, path restriction,
  surgical jq-merge for settings) that inline logic would miss.
- **Never delete project items.** Skills/agents/MCP servers/plugins that exist
  in the project but not in the seed are intentional — leave them alone and
  report them as preserved.
- **Never widen scope to docs or infra.** This skill syncs Claude tooling only.
  If the user asks to also update docs or hooks, point them to
  `scripts/update-from-seed.sh` — do not expand this skill's responsibilities.
- **Flag the restart requirement.** Claude Code loads skills, agents, MCP
  servers, and the plugin list at session start. The user needs to exit and
  re-enter for new tooling to be active.
