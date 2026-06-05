# hermes-skill

Hermes is an agent skill for driving the **Vulcan Product Suite** (projects, sprints, tasks, documents, activity feeds) from any Claude Code / Codex / agent host that supports the `npx skills` installer.

It wraps the [`vulcan` MCP server](https://www.npmjs.com/package/vulcan-mcp-server) with conventions, recipes, and tier-aware rules so your agent uses Vulcan correctly out of the box.

## Install

```bash
npx skills add <your-org>/hermes-skill
```

The CLI drops the skill into your host's skill directory and the agent auto-discovers it.

## Prerequisites

Hermes provides guidance only — the actual tools come from the `vulcan` MCP server. You must register that server in your host's MCP config before Hermes does anything useful. See the `## Prerequisites` section inside [`skills/hermes/SKILL.md`](./skills/hermes/SKILL.md) for the exact JSON snippet and verification steps.

You'll need:

- A Vulcan API token (Vulcan → Settings → API Tokens).
- The base URL of your Vulcan API (`https://…/api/v1`).

## What's inside

| File | Purpose |
| --- | --- |
| [`skills/hermes/SKILL.md`](./skills/hermes/SKILL.md) | The skill itself — frontmatter + agent instructions. |
| `README.md` | This file. |

## Smoke test

In a fresh agent session after install:

> "use hermes to check my vulcan auth status"

Expected: the agent calls `mcp__vulcan__auth_status` and reports your name/email. If you see "tool not found", revisit the Prerequisites section.

## Contributing

Patches welcome. The skill body is one file — edit `skills/hermes/SKILL.md`, run any host-specific lint, open a PR.

## License

MIT.
