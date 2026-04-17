#!/bin/bash
# DevHawk — Install global Claude Code slash command, plugin, and integrations
#
# First run:  bash <(gh api repos/fractionwork/devhawk-seed/contents/scripts/install-global-command.sh --jq '.content | @base64d')
# Reinstall:  Same command — safely overwrites slash command, skips what's already set up
# After this, /devhawk-new is available in any Claude Code session.

set -e

echo ""
echo "╔══════════════════════════════════════╗"
echo "║  DevHawk — Developer Machine Setup   ║"
echo "╚══════════════════════════════════════╝"
echo ""

# ── Detect platform ──
OS="$(uname -s)"
case "$OS" in
  Darwin) PLATFORM="mac" ;;
  Linux)  PLATFORM="linux" ;;
  *)      PLATFORM="unknown" ;;
esac
echo "Platform: $OS ($PLATFORM)"
echo ""

# ── Check prerequisites ──
echo "Checking prerequisites..."
echo ""
PASS=0
FAIL=0

check() {
  local cmd="$1"
  local install_mac="$2"
  local install_linux="$3"

  if command -v "$cmd" >/dev/null 2>&1; then
    local ver
    ver=$("$cmd" --version 2>/dev/null | head -1 || echo "installed")
    echo "  ✓ $cmd — $ver"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $cmd — NOT FOUND"
    if [ "$PLATFORM" = "mac" ]; then
      echo "    Install: $install_mac"
    elif [ "$PLATFORM" = "linux" ]; then
      echo "    Install: $install_linux"
    fi
    FAIL=$((FAIL + 1))
  fi
}

check "node"    "brew install node (or: nvm install 22)"       "nvm install 22"

# pnpm via corepack can hang on first run — check separately
if command -v pnpm >/dev/null 2>&1; then
  ver=$(timeout 5 pnpm --version 2>/dev/null | head -1 || echo "installed")
  echo "  ✓ pnpm — $ver"
  PASS=$((PASS + 1))
else
  echo "  ✗ pnpm — NOT FOUND"
  echo "    Install: corepack enable pnpm"
  FAIL=$((FAIL + 1))
fi
check "docker"  "brew install --cask docker"                   "https://docs.docker.com/engine/install/"
check "gh"      "brew install gh"                              "sudo apt install gh (see: https://github.com/cli/cli/blob/trunk/docs/install_linux.md)"
# doctl uses "doctl version" not "--version"
if command -v doctl >/dev/null 2>&1; then
  ver=$(doctl version 2>/dev/null | head -1 || echo "installed")
  echo "  ✓ doctl — $ver"
  PASS=$((PASS + 1))
else
  echo "  ✗ doctl — NOT FOUND"
  if [ "$PLATFORM" = "mac" ]; then
    echo "    Install: brew install doctl"
  elif [ "$PLATFORM" = "linux" ]; then
    echo "    Install: sudo snap install doctl (or: https://docs.digitalocean.com/reference/doctl/how-to/install/)"
  fi
  FAIL=$((FAIL + 1))
fi
check "git"     "brew install git"                             "sudo apt install git"
check "jq"      "brew install jq"                              "sudo apt install jq"
check "pm2"     "npm install -g pm2"                           "npm install -g pm2"
check "claude"  "npm install -g @anthropic-ai/claude-code"     "npm install -g @anthropic-ai/claude-code"

echo ""
echo "  $PASS passed, $FAIL missing"
echo ""

# ── Check auth status ──
echo "Checking authentication..."
echo ""

if command -v gh >/dev/null 2>&1; then
  if gh auth status >/dev/null 2>&1; then
    echo "  ✓ GitHub CLI — authenticated"
  else
    echo "  ✗ GitHub CLI — not authenticated"
    echo "    Run: gh auth login"
  fi
else
  echo "  — GitHub CLI — not installed (skipped)"
fi

# Check for SSH key (needed for git clone over SSH)
if [ -f "$HOME/.ssh/id_ed25519.pub" ] || [ -f "$HOME/.ssh/id_rsa.pub" ]; then
  if ssh -T git@github.com 2>&1 | grep -qi "successfully authenticated"; then
    echo "  ✓ GitHub SSH — key registered"
  else
    echo "  ⚠ GitHub SSH — key exists locally but not verified with GitHub"
    echo "    Run: gh ssh-key add ~/.ssh/id_ed25519.pub --title \"$(hostname)\""
    echo "    Or manually: https://github.com/settings/ssh/new"
  fi
else
  echo "  ✗ GitHub SSH — no key found"
  echo "    Generate a key and add it to GitHub:"
  if [ "$PLATFORM" = "mac" ]; then
    echo "      ssh-keygen -t ed25519 -C \"your@email.com\""
    echo "      eval \"\$(ssh-agent -s)\" && ssh-add --apple-use-keychain ~/.ssh/id_ed25519"
    echo "      gh ssh-key add ~/.ssh/id_ed25519.pub --title \"$(hostname)\""
  else
    echo "      ssh-keygen -t ed25519 -C \"your@email.com\""
    echo "      eval \"\$(ssh-agent -s)\" && ssh-add ~/.ssh/id_ed25519"
    echo "      gh ssh-key add ~/.ssh/id_ed25519.pub --title \"$(hostname)\""
  fi
  echo "    Or manually: https://github.com/settings/ssh/new"
fi

if command -v doctl >/dev/null 2>&1; then
  if doctl account get >/dev/null 2>&1; then
    echo "  ✓ DigitalOcean CLI — authenticated"
  else
    echo "  ✗ DigitalOcean CLI — not authenticated"
    echo "    Run: doctl auth init"
    echo "    Token: https://cloud.digitalocean.com/account/api/tokens"
  fi
else
  echo "  — DigitalOcean CLI — not installed (skipped)"
fi

echo ""

# ── Install slash command ──
COMMANDS_DIR="$HOME/.claude/commands"
mkdir -p "$COMMANDS_DIR"
COMMAND_EXISTS=false
if [ -f "$COMMANDS_DIR/devhawk-new.md" ]; then
  COMMAND_EXISTS=true
fi
echo "Installing Claude Code slash command..."

cat > "$COMMANDS_DIR/devhawk-new.md" << 'COMMAND'
# DevHawk: New project

Start a new project on the DevHawk Reference Stack. Clone the seed, install dependencies, start backing services, and prepare for bootstrap.

## Arguments
- $ARGUMENTS: Project name in kebab-case (e.g., "talon-dashboard", "client-portal")

## Steps

1. Clone the DevHawk seed repo and set up a fresh git history:
```bash
git clone git@github.com:fractionwork/devhawk-seed.git $ARGUMENTS
cd $ARGUMENTS
rm -rf .git
git init
git add -A
git commit -m "feat: scaffold from devhawk-seed"
```

2. Install dependencies:
```bash
pnpm install
```

3. Sanity-check Docker is available and warm the image cache. Do NOT start containers yet — bootstrap will rename the compose project, DB user, and port mappings in Phase 2 to avoid collisions with other projects. Starting Docker before that rename would just create containers we'd immediately tear down, and risks port/name collisions if the seed defaults are already in use by another project.
```bash
docker info >/dev/null 2>&1 || { echo "Docker daemon not running — please start Docker Desktop"; exit 1; }
docker compose -f docker/docker-compose.dev.yml pull
```

4. Set up environment and generate a real auth secret:
```bash
cp .env.example .env.local
```
Then replace the placeholder `BETTER_AUTH_SECRET` value in `.env.local` with a real secret:
```bash
SECRET=$(openssl rand -base64 32)
sed -i.bak "s|change-me-generate-with-openssl-rand-base64-32|$SECRET|" .env.local && rm -f .env.local.bak
```

5. Verify the seed compiles:
```bash
pnpm typecheck
```

After all steps complete, tell the user:

> **$ARGUMENTS is ready.** Docker verified and images pulled. Environment configured.
> Backing services will start after bootstrap's Phase 2 renames the compose project to avoid collisions with other projects.
> Migrations will run automatically after the bootstrap scaffold is generated.

Then IMMEDIATELY begin the bootstrap process yourself. Do NOT tell the user to type "bootstrap" or try to invoke a skill tool. The bootstrap skill is already loaded as project context from `.claude/skills/bootstrap/SKILL.md`. Read it and start Phase 1 (Product Discovery) by asking the opening questions directly.

If the user provided a product description alongside the project name, use that as the starting input for discovery.
COMMAND

if [ "$COMMAND_EXISTS" = true ]; then
  echo "  ✓ /devhawk-new updated at $COMMANDS_DIR/devhawk-new.md"
else
  echo "  ✓ /devhawk-new installed at $COMMANDS_DIR/devhawk-new.md"
fi
echo ""

# ── Install frontend-design plugin ──
if command -v claude >/dev/null 2>&1; then
  echo "Installing frontend-design plugin..."
  if claude plugins list 2>/dev/null | grep -q "frontend-design"; then
    echo "  ✓ frontend-design plugin — already installed"
  else
    if claude plugin install frontend-design 2>/dev/null; then
      echo "  ✓ frontend-design plugin — installed"
    else
      echo "  ✗ frontend-design plugin — install failed"
      echo "    Run manually: claude plugin install frontend-design"
    fi
  fi
  echo ""
fi

# ── Project management MCP setup (Asana / Jira) ──
if command -v claude >/dev/null 2>&1; then
  echo "Checking project management MCP connections..."
  echo ""

  ASANA_CONNECTED=false
  JIRA_CONNECTED=false

  if claude mcp list 2>/dev/null | grep -qi "asana.*Connected"; then
    echo "  ✓ Asana MCP — already connected"
    ASANA_CONNECTED=true
  fi

  if claude mcp list 2>/dev/null | grep -qi "jira.*Connected"; then
    echo "  ✓ Jira Cloud MCP — already connected"
    JIRA_CONNECTED=true
  fi

  if [ "$ASANA_CONNECTED" = false ] && [ "$JIRA_CONNECTED" = false ]; then
    echo "  — No project management MCP connected"
    echo ""
    echo "  The bootstrap skill can automatically create project backlogs in Asana or Jira."
    echo "  Which would you like to set up? (asana/jira/both/skip)"
    read -r PM_CHOICE
  elif [ "$ASANA_CONNECTED" = false ]; then
    echo ""
    echo "  Would you also like to connect Asana? (y/n)"
    read -r ALSO_ASANA
    if [ "$ALSO_ASANA" = "y" ] || [ "$ALSO_ASANA" = "Y" ]; then
      PM_CHOICE="asana"
    else
      PM_CHOICE="skip"
    fi
  elif [ "$JIRA_CONNECTED" = false ]; then
    echo ""
    echo "  Would you also like to connect Jira Cloud? (y/n)"
    read -r ALSO_JIRA
    if [ "$ALSO_JIRA" = "y" ] || [ "$ALSO_JIRA" = "Y" ]; then
      PM_CHOICE="jira"
    else
      PM_CHOICE="skip"
    fi
  else
    PM_CHOICE="skip"
  fi

  # ── Asana setup ──
  if [ "$PM_CHOICE" = "asana" ] || [ "$PM_CHOICE" = "both" ]; then
    echo ""
    echo "  ┌─────────────────────────────────────────────────────┐"
    echo "  │  Asana MCP Setup                                     │"
    echo "  └─────────────────────────────────────────────────────┘"
    echo ""
    echo "  1. Open https://app.asana.com/0/my-apps in your browser"
    echo "  2. Click 'Create new app' → name it 'Claude Code MCP' → select 'MCP app'"
    echo "  3. Click 'Create app' — save your Client ID"
    echo "  4. In the left sidebar, click 'OAuth' → add redirect URL:"
    echo "     http://localhost:8080/callback"
    echo "  5. Click 'Manage distribution' → choose your workspace(s) → Save"
    echo ""
    read -r -p "  Asana Client ID (or Enter to skip): " ASANA_CLIENT_ID

    if [ -n "$ASANA_CLIENT_ID" ]; then
      echo ""
      echo "  Connecting to Asana... (a browser window will open for authorization)"
      echo ""
      claude mcp add --transport http \
        --client-id "$ASANA_CLIENT_ID" \
        --client-secret \
        --callback-port 8080 \
        asana https://mcp.asana.com/v2/mcp
      echo ""
      echo "  ✓ Asana MCP configured"
    else
      echo "  Skipped Asana — re-run this script to set up later."
    fi
    echo ""
  fi

  # ── Jira setup ──
  if [ "$PM_CHOICE" = "jira" ] || [ "$PM_CHOICE" = "both" ]; then
    echo ""
    echo "  ┌─────────────────────────────────────────────────────┐"
    echo "  │  Jira Cloud MCP Setup                                │"
    echo "  └─────────────────────────────────────────────────────┘"
    echo ""
    echo "  1. Go to https://developer.atlassian.com/console/myapps/"
    echo "  2. Click 'Create' → 'OAuth 2.0 integration'"
    echo "  3. Name it 'Claude Code MCP' → Create"
    echo "  4. Under 'Authorization', click 'Add' next to 'OAuth 2.0 (3LO)'"
    echo "  5. Set callback URL to: http://localhost:8080/callback"
    echo "  6. Under 'Permissions', add 'Jira API' with these scopes:"
    echo "     read:jira-work, write:jira-work, read:jira-user"
    echo "  7. Under 'Settings', copy your Client ID"
    echo ""
    read -r -p "  Jira Client ID (or Enter to skip): " JIRA_CLIENT_ID

    if [ -n "$JIRA_CLIENT_ID" ]; then
      echo ""
      echo "  Connecting to Jira... (a browser window will open for authorization)"
      echo ""
      claude mcp add --transport http \
        --client-id "$JIRA_CLIENT_ID" \
        --client-secret \
        --callback-port 8080 \
        jira-cloud https://mcp.atlassian.com/v1/mcp
      echo ""
      echo "  ✓ Jira Cloud MCP configured"
    else
      echo "  Skipped Jira — re-run this script to set up later."
    fi
    echo ""
  fi

  if [ "$PM_CHOICE" = "skip" ] && [ "$ASANA_CONNECTED" = false ] && [ "$JIRA_CONNECTED" = false ]; then
    echo ""
    echo "  Skipped. To set up later, re-run this script or follow the"
    echo "  instructions in the README under 'Project management MCP setup'."
    echo ""
  fi
fi

# ── Summary ──
echo "╔══════════════════════════════════════╗"
echo "║  Setup complete                      ║"
echo "╚══════════════════════════════════════╝"
echo ""
echo "  Installed:"
echo "    ✓ /devhawk-new slash command"
echo "    ✓ frontend-design plugin"
echo ""
echo "  In Claude Code, run:"
echo "    /devhawk-new my-project-name"
echo ""
