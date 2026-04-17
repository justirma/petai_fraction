#!/bin/bash
# DevHawk — Update skills and docs from the seed repo
#
# Run from inside an existing DevHawk project:
#   bash <(curl -fsSL https://raw.githubusercontent.com/fractionwork/devhawk-seed/main/scripts/update-from-seed.sh)
#
# Or if you have the seed cloned locally:
#   bash /path/to/devhawk-seed/scripts/update-from-seed.sh
#
# Updates skills, commands, reference docs, and enforcement hooks from the
# latest seed. Does NOT touch project-specific files (schema, routes, etc.)
# or the project-specific section at the top of CLAUDE.md.

set -e

SEED_REPO="fractionwork/devhawk-seed"
SEED_BRANCH="main"

echo ""
echo "╔══════════════════════════════════════╗"
echo "║  DevHawk — Update from Seed          ║"
echo "╚══════════════════════════════════════╝"
echo ""

# ── Verify we're in a DevHawk project ──
if [ ! -f "CLAUDE.md" ] || ! grep -q "DevHawk" CLAUDE.md 2>/dev/null; then
  echo "  ✗ Not a DevHawk project (no CLAUDE.md with DevHawk found)"
  echo "    Run this from the root of a DevHawk project."
  exit 1
fi

# ── Verify gh CLI is available and authenticated ──
if ! command -v gh >/dev/null 2>&1; then
  echo "  ✗ GitHub CLI (gh) is required but not installed"
  echo "    Install: brew install gh (macOS) or see https://github.com/cli/cli"
  exit 1
fi
if ! gh auth status >/dev/null 2>&1; then
  echo "  ✗ GitHub CLI not authenticated"
  echo "    Run: gh auth login"
  exit 1
fi

echo "  Project: $(basename "$(pwd)")"
echo ""

# ── Helper to download a file from the seed repo ──
download() {
  local remote_path="$1"
  local local_path="$2"
  local label="$3"

  mkdir -p "$(dirname "$local_path")"

  if gh api "repos/$SEED_REPO/contents/$remote_path?ref=$SEED_BRANCH" \
       --jq '.content | @base64d' 2>/dev/null > "$local_path.tmp" 2>/dev/null; then
    if [ -f "$local_path" ] && diff -q "$local_path" "$local_path.tmp" >/dev/null 2>&1; then
      rm "$local_path.tmp"
      echo "  — $label (unchanged)"
    else
      mv "$local_path.tmp" "$local_path"
      echo "  ✓ $label (updated)"
      UPDATED=$((UPDATED + 1))
    fi
  else
    rm -f "$local_path.tmp"
    echo "  ✗ $label (download failed)"
    FAILED=$((FAILED + 1))
  fi
}

UPDATED=0
FAILED=0

# ── Update skills ──
echo "Updating skills..."
download ".claude/skills/bootstrap/SKILL.md"     ".claude/skills/bootstrap/SKILL.md"     "bootstrap skill"
download ".claude/skills/feature-build/SKILL.md"  ".claude/skills/feature-build/SKILL.md"  "feature-build skill"
download ".claude/skills/devhawk-stack/SKILL.md"  ".claude/skills/devhawk-stack/SKILL.md"  "devhawk-stack skill"
download ".claude/skills/migrate/SKILL.md"        ".claude/skills/migrate/SKILL.md"        "migrate skill"
echo ""

# ── Update commands ──
echo "Updating commands..."
download ".claude/commands/provision.md"           ".claude/commands/provision.md"           "provision command"
echo ""

# ── Update reference docs ──
echo "Updating reference docs..."
download "docs/conventions.md"       "docs/conventions.md"       "conventions.md"
download "docs/architecture.md"      "docs/architecture.md"      "architecture.md"
download "docs/database-patterns.md" "docs/database-patterns.md" "database-patterns.md"
download "docs/auth-patterns.md"     "docs/auth-patterns.md"     "auth-patterns.md"
download "docs/background-jobs.md"   "docs/background-jobs.md"   "background-jobs.md"
download "docs/ai-patterns.md"       "docs/ai-patterns.md"       "ai-patterns.md"
download "docs/testing-patterns.md"  "docs/testing-patterns.md"  "testing-patterns.md"
download "docs/deployment.md"        "docs/deployment.md"        "deployment.md"
echo ""

# ── Update hooks config ──
echo "Updating hooks..."
download ".claude/settings.json"     ".claude/settings.json"     "settings.json (hooks)"
echo ""

# ── Update infrastructure files ──
echo "Updating infrastructure..."
download "docker/Dockerfile"              "docker/Dockerfile"              "Dockerfile (web)"
download "docker/Dockerfile.worker"       "docker/Dockerfile.worker"       "Dockerfile (worker)"
download "docker/docker-compose.dev.yml"  "docker/docker-compose.dev.yml"  "docker-compose.dev.yml"
download "ecosystem.config.cjs"           "ecosystem.config.cjs"           "ecosystem.config.cjs"
download "vitest.config.ts"               "vitest.config.ts"               "vitest.config.ts"
echo ""

# ── Files we DON'T update ──
echo "Preserved (project-specific):"
echo "  — CLAUDE.md (has project addendum)"
echo "  — README.md"
echo "  — lib/db/schema/ (project schema)"
echo "  — lib/auth.ts, lib/auth-client.ts"
echo "  — app/ (project routes and pages)"
echo "  — package.json"
echo ""

# ── Summary ──
if [ "$FAILED" -gt 0 ]; then
  echo "  $UPDATED updated, $FAILED failed"
  echo "  Check your network connection and try again."
elif [ "$UPDATED" -gt 0 ]; then
  echo "  $UPDATED file(s) updated."
  echo ""
  echo "  Review changes:"
  echo "    git diff"
  echo ""
  echo "  If everything looks good:"
  echo "    git add -A && git commit -m \"chore: update skills and docs from devhawk-seed\""
else
  echo "  Everything up to date."
fi
echo ""
