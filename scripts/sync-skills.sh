#!/bin/bash
# DevHawk — Sync Claude tooling from the seed repo
#
# Pulls the latest version of seed-managed Claude artifacts into the current
# project. Discovers everything dynamically — anything new added to the seed
# is picked up automatically.
#
# Scope (in order):
#   1. .claude/skills/<name>/         — full directory overwrite per skill
#   2. .claude/agents/<name>.md       — single-file overwrite per agent
#   3. .mcp.json                      — jq-merged: seed mcpServers entries
#                                       overwrite same-named project entries;
#                                       project-added MCP servers are preserved
#   4. .claude/settings.json          — jq-merged: ONLY the enabledPlugins and
#                                       extraKnownMarketplaces keys are touched.
#                                       Permissions, hooks, and everything else
#                                       are left untouched.
#
# Usage (requires `gh` CLI authenticated — the seed repo is private):
#   bash <(gh api repos/fractionwork/devhawk-seed/contents/scripts/sync-skills.sh?ref=main --jq '.content | @base64d')
#   bash scripts/sync-skills.sh                # if already in the project
#   bash scripts/sync-skills.sh --dry-run      # preview without writing
#   bash scripts/sync-skills.sh --only bootstrap cost-estimate   # sync specific skills/agents by name
#   bash scripts/sync-skills.sh --skip-mcp     # skip .mcp.json merge
#   bash scripts/sync-skills.sh --skip-settings # skip .claude/settings.json merge
#
# Behavior:
#   - Always fetches from GitHub via `gh api` (fractionwork/devhawk-seed@main) unless --source is given.
#   - Overwrites by-name without per-item confirmation. Pre-overwrite backups
#     land in .claude/skills/.backup/<timestamp>/ (also covers agents, .mcp.json,
#     and the settings snapshot).
#   - NEVER removes skills/agents/MCP servers/plugins that exist in the project
#     but not in the seed — project additions are preserved.
#   - Items with frontmatter flag `seed_managed: false` are skipped.
#   - Hard-fails if asked to write outside .claude/skills, .claude/agents,
#     .claude/settings.json, or .mcp.json.

set -euo pipefail

SEED_REPO="${SEED_REPO:-fractionwork/devhawk-seed}"
SEED_BRANCH="${SEED_BRANCH:-main}"

DRY_RUN=0
SKIP_MCP=0
SKIP_SETTINGS=0
ONLY=()
SOURCE_DIR=""

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)        DRY_RUN=1; shift ;;
    --skip-mcp)       SKIP_MCP=1; shift ;;
    --skip-settings)  SKIP_SETTINGS=1; shift ;;
    --source)         SOURCE_DIR="$2"; shift 2 ;;
    --only)           shift; while [ $# -gt 0 ] && [[ "$1" != --* ]]; do ONLY+=("$1"); shift; done ;;
    -h|--help)        sed -n '2,40p' "$0"; exit 0 ;;
    *)                echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

echo ""
echo "╔══════════════════════════════════════╗"
echo "║  DevHawk — Sync Tooling from Seed    ║"
echo "╚══════════════════════════════════════╝"
echo ""

# ── Verify we're in a project root ──
if [ ! -d ".claude" ] && [ ! -f "CLAUDE.md" ]; then
  echo "  ✗ Doesn't look like a Claude-enabled project (no .claude/ or CLAUDE.md)."
  echo "    Run this from the project root."
  exit 1
fi

mkdir -p .claude/skills

# ── Resolve source ──
TMP=""
cleanup() { [ -n "$TMP" ] && rm -rf "$TMP"; }
trap cleanup EXIT

if [ -n "$SOURCE_DIR" ]; then
  if [ ! -d "$SOURCE_DIR/.claude" ]; then
    echo "  ✗ --source '$SOURCE_DIR' has no .claude directory"
    exit 1
  fi
  SEED_ROOT="$SOURCE_DIR"
  echo "  Source: local clone at $SOURCE_DIR"
else
  if ! command -v gh >/dev/null 2>&1; then
    echo "  ✗ GitHub CLI (gh) is required — the seed repo is private."
    echo "    Install: https://github.com/cli/cli"
    exit 1
  fi
  if ! gh auth status >/dev/null 2>&1; then
    echo "  ✗ GitHub CLI not authenticated. Run: gh auth login"
    exit 1
  fi
  if ! command -v tar >/dev/null 2>&1; then
    echo "  ✗ tar is required"; exit 1
  fi
  TMP="$(mktemp -d)"
  echo "  Source: gh api repos/${SEED_REPO}/tarball/${SEED_BRANCH}"
  echo "  Fetching..."
  gh api "repos/${SEED_REPO}/tarball/${SEED_BRANCH}" > "$TMP/seed.tar.gz"
  tar -xz -C "$TMP" -f "$TMP/seed.tar.gz"
  rm "$TMP/seed.tar.gz"
  # Tarball unpacks to <user>-<repo>-<sha>/
  SEED_ROOT="$(find "$TMP" -maxdepth 1 -type d ! -path "$TMP" | head -n1)"
  if [ -z "$SEED_ROOT" ] || [ ! -d "$SEED_ROOT/.claude" ]; then
    echo "  ✗ Tarball did not contain .claude/"
    exit 1
  fi
fi

SEED_SKILLS="$SEED_ROOT/.claude/skills"
SEED_AGENTS="$SEED_ROOT/.claude/agents"
SEED_MCP="$SEED_ROOT/.mcp.json"
SEED_SETTINGS="$SEED_ROOT/.claude/settings.json"

PROJ_MCP=".mcp.json"
PROJ_SETTINGS=".claude/settings.json"

# Need jq for .mcp.json + settings merging
if [ "$SKIP_MCP" -eq 0 ] || [ "$SKIP_SETTINGS" -eq 0 ]; then
  if ! command -v jq >/dev/null 2>&1; then
    echo "  ✗ jq is required for .mcp.json / settings.json merging."
    echo "    Install jq, or pass --skip-mcp --skip-settings to bypass."
    exit 1
  fi
fi

echo "  Project: $(basename "$(pwd)")"
[ "$DRY_RUN" -eq 1 ] && echo "  Mode: DRY RUN (no files will be written)"
echo ""

# ── Backup setup ──
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".claude/skills/.backup/${TIMESTAMP}"

should_sync() {
  local name="$1"
  if [ "${#ONLY[@]}" -eq 0 ]; then return 0; fi
  for n in "${ONLY[@]}"; do [ "$n" = "$name" ] && return 0; done
  return 1
}

is_seed_managed_false() {
  # Check if a frontmatter-bearing .md file has `seed_managed: false`
  local md="$1"
  [ -f "$md" ] || return 1
  awk '/^---$/{n++; next} n==1' "$md" 2>/dev/null \
    | grep -Eq '^seed_managed:[[:space:]]*false[[:space:]]*$'
}

ensure_backup_dir() {
  [ "$DRY_RUN" -eq 1 ] && return 0
  mkdir -p "$BACKUP_DIR"
}

# ════════════════════════════════════════════════════════════════════
# 1. Skills
# ════════════════════════════════════════════════════════════════════

ADDED_S=0; UPDATED_S=0; SKIPPED_S=0; PROTECTED_S=0

if [ -d "$SEED_SKILLS" ]; then
  echo "Syncing skills..."
  for seed_skill_dir in "$SEED_SKILLS"/*/; do
    name="$(basename "$seed_skill_dir")"
    should_sync "$name" || continue

    project_skill_dir=".claude/skills/$name"
    project_skill_md="$project_skill_dir/SKILL.md"

    # Safety: never write outside .claude/skills
    case "$project_skill_dir" in
      .claude/skills/*) ;;
      *) echo "  ✗ refusing to write outside .claude/skills ($project_skill_dir)"; exit 1 ;;
    esac

    if is_seed_managed_false "$project_skill_md"; then
      echo "  ⊘ $name (seed_managed: false — preserved)"
      PROTECTED_S=$((PROTECTED_S+1))
      continue
    fi

    existed=0
    [ -d "$project_skill_dir" ] && existed=1

    if [ "$existed" -eq 1 ] && diff -qr "$seed_skill_dir" "$project_skill_dir" >/dev/null 2>&1; then
      echo "  — $name (unchanged)"
      SKIPPED_S=$((SKIPPED_S+1))
      continue
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
      if [ "$existed" -eq 1 ]; then
        echo "  ✎ $name (would update)"; UPDATED_S=$((UPDATED_S+1))
      else
        echo "  + $name (would add)"; ADDED_S=$((ADDED_S+1))
      fi
      continue
    fi

    if [ "$existed" -eq 1 ]; then
      ensure_backup_dir
      cp -R "$project_skill_dir" "$BACKUP_DIR/skill__$name"
    fi

    rm -rf "$project_skill_dir"
    mkdir -p "$project_skill_dir"
    cp -R "$seed_skill_dir"/. "$project_skill_dir"/

    if [ "$existed" -eq 1 ]; then
      echo "  ✎ $name (updated)"; UPDATED_S=$((UPDATED_S+1))
    else
      echo "  + $name (added)"; ADDED_S=$((ADDED_S+1))
    fi
  done

  # Report preserved project-only skills
  PRESERVED_S=()
  for proj_skill_dir in .claude/skills/*/; do
    [ -d "$proj_skill_dir" ] || continue
    n="$(basename "$proj_skill_dir")"
    [ "$n" = ".backup" ] && continue
    [ ! -d "$SEED_SKILLS/$n" ] && PRESERVED_S+=("$n")
  done
  if [ "${#PRESERVED_S[@]}" -gt 0 ]; then
    echo "  Project-only skills (preserved):"
    for n in "${PRESERVED_S[@]}"; do echo "    · $n"; done
  fi
  echo ""
fi

# ════════════════════════════════════════════════════════════════════
# 2. Agents
# ════════════════════════════════════════════════════════════════════

ADDED_A=0; UPDATED_A=0; SKIPPED_A=0; PROTECTED_A=0

if [ -d "$SEED_AGENTS" ]; then
  echo "Syncing agents..."
  mkdir -p .claude/agents
  for seed_agent_md in "$SEED_AGENTS"/*.md; do
    [ -f "$seed_agent_md" ] || continue
    fname="$(basename "$seed_agent_md")"
    name="${fname%.md}"
    should_sync "$name" || continue

    project_agent_md=".claude/agents/$fname"

    case "$project_agent_md" in
      .claude/agents/*) ;;
      *) echo "  ✗ refusing to write outside .claude/agents ($project_agent_md)"; exit 1 ;;
    esac

    if is_seed_managed_false "$project_agent_md"; then
      echo "  ⊘ $name (seed_managed: false — preserved)"
      PROTECTED_A=$((PROTECTED_A+1))
      continue
    fi

    existed=0
    [ -f "$project_agent_md" ] && existed=1

    if [ "$existed" -eq 1 ] && diff -q "$seed_agent_md" "$project_agent_md" >/dev/null 2>&1; then
      echo "  — $name (unchanged)"
      SKIPPED_A=$((SKIPPED_A+1))
      continue
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
      if [ "$existed" -eq 1 ]; then
        echo "  ✎ $name (would update)"; UPDATED_A=$((UPDATED_A+1))
      else
        echo "  + $name (would add)"; ADDED_A=$((ADDED_A+1))
      fi
      continue
    fi

    if [ "$existed" -eq 1 ]; then
      ensure_backup_dir
      cp "$project_agent_md" "$BACKUP_DIR/agent__$fname"
    fi
    cp "$seed_agent_md" "$project_agent_md"

    if [ "$existed" -eq 1 ]; then
      echo "  ✎ $name (updated)"; UPDATED_A=$((UPDATED_A+1))
    else
      echo "  + $name (added)"; ADDED_A=$((ADDED_A+1))
    fi
  done

  PRESERVED_A=()
  if [ -d ".claude/agents" ]; then
    for proj_agent_md in .claude/agents/*.md; do
      [ -f "$proj_agent_md" ] || continue
      n="$(basename "$proj_agent_md" .md)"
      [ ! -f "$SEED_AGENTS/$n.md" ] && PRESERVED_A+=("$n")
    done
  fi
  if [ "${#PRESERVED_A[@]}" -gt 0 ]; then
    echo "  Project-only agents (preserved):"
    for n in "${PRESERVED_A[@]}"; do echo "    · $n"; done
  fi
  echo ""
fi

# ════════════════════════════════════════════════════════════════════
# 3. .mcp.json — merge mcpServers entries
# ════════════════════════════════════════════════════════════════════

MCP_CHANGED=0
if [ "$SKIP_MCP" -eq 0 ] && [ -f "$SEED_MCP" ]; then
  echo "Syncing .mcp.json..."

  if [ ! -f "$PROJ_MCP" ]; then
    echo '{"mcpServers": {}}' > "/tmp/__seed_mcp_base.json"
    PROJ_MCP_INPUT="/tmp/__seed_mcp_base.json"
  else
    PROJ_MCP_INPUT="$PROJ_MCP"
  fi

  MERGED="$(jq -s '
    .[0] as $seed | .[1] as $proj |
    $proj | .mcpServers = ((.mcpServers // {}) + ($seed.mcpServers // {}))
  ' "$SEED_MCP" "$PROJ_MCP_INPUT")"

  # Are we adding/changing anything?
  if [ -f "$PROJ_MCP" ] && [ "$MERGED" = "$(jq . "$PROJ_MCP")" ]; then
    echo "  — mcpServers (unchanged)"
  else
    SEED_NAMES="$(jq -r '.mcpServers | keys[]' "$SEED_MCP" 2>/dev/null | tr '\n' ',' | sed 's/,$//')"
    if [ "$DRY_RUN" -eq 1 ]; then
      echo "  ✎ would merge seed mcpServers entries: ${SEED_NAMES}"
      MCP_CHANGED=1
    else
      [ -f "$PROJ_MCP" ] && { ensure_backup_dir; cp "$PROJ_MCP" "$BACKUP_DIR/mcp.json"; }
      echo "$MERGED" > "$PROJ_MCP"
      echo "  ✎ merged mcpServers entries: ${SEED_NAMES}"
      MCP_CHANGED=1
    fi
  fi
  echo ""
fi

# ════════════════════════════════════════════════════════════════════
# 4. .claude/settings.json — surgical merge of plugin keys only
# ════════════════════════════════════════════════════════════════════

SETTINGS_CHANGED=0
if [ "$SKIP_SETTINGS" -eq 0 ] && [ -f "$SEED_SETTINGS" ]; then
  echo "Syncing .claude/settings.json (enabledPlugins + extraKnownMarketplaces only)..."

  if [ ! -f "$PROJ_SETTINGS" ]; then
    echo '{}' > "/tmp/__seed_settings_base.json"
    PROJ_SETTINGS_INPUT="/tmp/__seed_settings_base.json"
  else
    PROJ_SETTINGS_INPUT="$PROJ_SETTINGS"
  fi

  MERGED="$(jq -s '
    .[0] as $seed | .[1] as $proj |
    $proj
    | if ($seed.enabledPlugins // null) then
        .enabledPlugins = ((.enabledPlugins // {}) + $seed.enabledPlugins)
      else . end
    | if ($seed.extraKnownMarketplaces // null) then
        .extraKnownMarketplaces = (((.extraKnownMarketplaces // []) + $seed.extraKnownMarketplaces) | unique)
      else . end
  ' "$SEED_SETTINGS" "$PROJ_SETTINGS_INPUT")"

  if [ -f "$PROJ_SETTINGS" ] && [ "$MERGED" = "$(jq . "$PROJ_SETTINGS")" ]; then
    echo "  — enabledPlugins / extraKnownMarketplaces (unchanged)"
  else
    SEED_PLUGINS="$(jq -r '.enabledPlugins // {} | keys[]' "$SEED_SETTINGS" 2>/dev/null | tr '\n' ',' | sed 's/,$//')"
    if [ "$DRY_RUN" -eq 1 ]; then
      echo "  ✎ would enable plugins: ${SEED_PLUGINS:-(none in seed)}"
      echo "    permissions/hooks/other keys: NOT touched"
      SETTINGS_CHANGED=1
    else
      [ -f "$PROJ_SETTINGS" ] && { ensure_backup_dir; cp "$PROJ_SETTINGS" "$BACKUP_DIR/settings.json"; }
      echo "$MERGED" > "$PROJ_SETTINGS"
      echo "  ✎ merged enabledPlugins: ${SEED_PLUGINS:-(none)}"
      echo "    permissions/hooks/other keys: untouched"
      SETTINGS_CHANGED=1
    fi
  fi
  echo ""
fi

# ════════════════════════════════════════════════════════════════════
# Summary
# ════════════════════════════════════════════════════════════════════

echo "Summary:"
echo "  skills:   $ADDED_S added · $UPDATED_S updated · $SKIPPED_S unchanged · $PROTECTED_S seed_managed:false"
[ -d "$SEED_AGENTS" ] && echo "  agents:   $ADDED_A added · $UPDATED_A updated · $SKIPPED_A unchanged · $PROTECTED_A seed_managed:false"
if [ "$SKIP_MCP" -eq 0 ] && [ -f "$SEED_MCP" ]; then
  if [ "$MCP_CHANGED" -eq 1 ]; then
    echo "  mcp.json: $([ "$DRY_RUN" -eq 1 ] && echo "would merge" || echo merged)"
  else
    echo "  mcp.json: unchanged"
  fi
fi
if [ "$SKIP_SETTINGS" -eq 0 ] && [ -f "$SEED_SETTINGS" ]; then
  if [ "$SETTINGS_CHANGED" -eq 1 ]; then
    echo "  settings: $([ "$DRY_RUN" -eq 1 ] && echo "would merge" || echo merged) (plugin keys only)"
  else
    echo "  settings: unchanged (plugin keys only)"
  fi
fi

if [ "$DRY_RUN" -eq 0 ] && [ -d "$BACKUP_DIR" ]; then
  echo "  Backups: $BACKUP_DIR"
fi
echo ""

CHANGES=$((ADDED_S + UPDATED_S + ADDED_A + UPDATED_A + MCP_CHANGED + SETTINGS_CHANGED))
if [ "$DRY_RUN" -eq 0 ] && [ "$CHANGES" -gt 0 ]; then
  echo "Review changes: git diff .claude/ .mcp.json"
  echo "Commit:         git add .claude/ .mcp.json && git commit -m \"chore: sync claude tooling from devhawk-seed\""
  echo ""
  echo "Restart Claude Code to pick up new/updated skills, agents, MCP servers, and plugins."
fi
