#!/usr/bin/env bash
#
# Hermes setup — one-command install for the Vulcan skill.
#
# What it does:
#   1. Installs the skill via `npx skills add`.
#   2. Prompts for VULCAN_TOKEN and VULCAN_API_URL.
#   3. Patches ~/.claude.json to register the `vulcan` MCP server (with a
#      timestamped backup). If a `vulcan` entry already exists, asks before
#      overwriting.
#   4. Reminds you to restart Claude Code.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/tbm26gagankapoor-create/hermes-skill/main/setup.sh | bash
# or, after cloning:
#   ./setup.sh
#
# Requires: node (for safe JSON editing), npx (ships with node).

set -euo pipefail

SKILL_REPO="tbm26gagankapoor-create/hermes-skill"
CONFIG_PATH="${CLAUDE_CONFIG_PATH:-$HOME/.claude.json}"

bold()  { printf '\033[1m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
red()   { printf '\033[31m%s\033[0m\n' "$*" >&2; }
warn()  { printf '\033[33m%s\033[0m\n' "$*"; }

require() {
  command -v "$1" >/dev/null 2>&1 || { red "Missing required command: $1"; exit 1; }
}

require node
require npx

bold "==> Hermes setup"
echo "Skill repo:   $SKILL_REPO"
echo "Config path:  $CONFIG_PATH"
echo

# ---------------------------------------------------------------------------
# Step 1: install the skill
# ---------------------------------------------------------------------------
bold "==> [1/3] Installing skill (npx skills add)"
if npx --yes skills add "$SKILL_REPO"; then
  green "Skill installed."
else
  red "npx skills add failed. Fix the error above and re-run."
  exit 1
fi
echo

# ---------------------------------------------------------------------------
# Step 2: collect credentials
# ---------------------------------------------------------------------------
bold "==> [2/3] Vulcan credentials"
echo "Generate a token in Vulcan → Settings → API Tokens."
echo "Default API URL is https://vulcan.example.com/api/v1 — change it for your instance."
echo

# Read from /dev/tty (not stdin) so the prompts work under `curl … | bash`,
# where stdin is the pipe from curl, not the user's terminal. Fall back to
# stdin only when no controlling TTY is available (e.g. CI smoke tests).
# `-r /dev/tty` reports true even with no controlling terminal, so we
# actually try to open it.
if (exec 3</dev/tty) 2>/dev/null; then
  exec 3</dev/tty
  PROMPT_FD=3
else
  PROMPT_FD=0
  warn "No TTY detected — reading credentials from stdin (non-interactive mode)."
fi

printf "VULCAN_TOKEN (vulcan_ak_...): " >&2
IFS= read -r VULCAN_TOKEN <&"$PROMPT_FD"
if [[ -z "$VULCAN_TOKEN" ]]; then
  red "Empty token — aborting."
  exit 1
fi

printf "VULCAN_API_URL [https://vulcan.example.com/api/v1]: " >&2
IFS= read -r VULCAN_API_URL <&"$PROMPT_FD"
VULCAN_API_URL="${VULCAN_API_URL:-https://vulcan.example.com/api/v1}"

echo

# ---------------------------------------------------------------------------
# Step 3: patch ~/.claude.json
# ---------------------------------------------------------------------------
bold "==> [3/3] Registering vulcan MCP server"

# Ensure parent dir exists.
mkdir -p "$(dirname "$CONFIG_PATH")"

# Create empty config if missing.
if [[ ! -f "$CONFIG_PATH" ]]; then
  echo "{}" > "$CONFIG_PATH"
  warn "Created new $CONFIG_PATH"
fi

# Back up.
BACKUP_PATH="${CONFIG_PATH}.bak.$(date +%Y%m%d-%H%M%S)"
cp "$CONFIG_PATH" "$BACKUP_PATH"
echo "Backed up existing config to $BACKUP_PATH"

# Patch with node — handles existing vulcan entry, preserves other keys.
node - "$CONFIG_PATH" "$VULCAN_TOKEN" "$VULCAN_API_URL" <<'NODE'
const fs = require('fs');
const [, , path, token, apiUrl] = process.argv;

let cfg;
try {
  const raw = fs.readFileSync(path, 'utf8').trim();
  cfg = raw ? JSON.parse(raw) : {};
} catch (err) {
  console.error(`Could not parse ${path}: ${err.message}`);
  process.exit(1);
}

cfg.mcpServers = cfg.mcpServers || {};

if (cfg.mcpServers.vulcan) {
  process.stderr.write('A `vulcan` MCP server entry already exists. Overwrite? [y/N] ');
  // Read one char from /dev/tty so the prompt isn't swallowed by the heredoc.
  let answer = '';
  try {
    answer = fs.readFileSync('/dev/tty', 'utf8').split('\n')[0].trim().toLowerCase();
  } catch {
    // No TTY (piped install) — default to overwrite with a warning.
    console.error('No TTY available; overwriting existing entry.');
    answer = 'y';
  }
  if (answer !== 'y' && answer !== 'yes') {
    console.error('Aborted by user. Existing config left untouched.');
    process.exit(2);
  }
}

cfg.mcpServers.vulcan = {
  command: 'npx',
  args: ['-y', 'vulcan-mcp-server'],
  env: {
    VULCAN_TOKEN: token,
    VULCAN_API_URL: apiUrl,
  },
};

fs.writeFileSync(path, JSON.stringify(cfg, null, 2) + '\n');
console.log('Wrote vulcan MCP entry to', path);
NODE

echo
green "==> Hermes setup complete."
echo
bold "Next steps:"
echo "  1. Restart Claude Code (so the new MCP server starts)."
echo "  2. In any session, try: \"use hermes to check my vulcan auth status\""
echo "     — it should report your name and email."
echo
echo "Backup of the previous config: $BACKUP_PATH"
