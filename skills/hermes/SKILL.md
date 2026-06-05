---
name: hermes
description: Hermes — run Vulcan Product Suite activities (projects, sprints, tasks, documents, activity feeds) through the `vulcan` MCP server. Trigger when the user wants to query, create, update, or report on Vulcan work-items, sprints, documents, comments, members, or activity. Phrases like "vulcan", "hermes", "my tasks", "active sprint", "today's activity", "create a story/bug/task", "approve the PRD", or "who's working on X" should all route here. Skip for non-Vulcan project management tools (Jira, Linear, GitHub Issues directly).
---

# Hermes — Vulcan Activities

Hermes is the front-door skill for everything in the Vulcan Product Suite. It wraps the `vulcan` MCP server so any teammate's agent can drive Vulcan with consistent conventions.

## Prerequisites

Hermes is **guidance only** — the actual tools (`mcp__vulcan__*`) come from the `vulcan` MCP server. If those tools are missing, you must configure the MCP server first:

1. **Generate an API token** in Vulcan → Settings → API Tokens. Keep it secret; it scopes to your tenant and user.
2. **Register the MCP server** in your host config (e.g. `~/.claude.json` for Claude Code, or `.mcp.json` in a project root):

   ```json
   {
     "mcpServers": {
       "vulcan": {
         "command": "npx",
         "args": ["-y", "vulcan-mcp-server"],
         "env": {
           "VULCAN_TOKEN": "vulcan_ak_...",
           "VULCAN_API_URL": "https://your-vulcan.example.com/api/v1"
         }
       }
     }
   }
   ```

   For HTTP / shared deployments, the same env vars apply to the running server; the host sends `Authorization: Bearer <token>` per request instead of using `VULCAN_TOKEN`.

3. **Verify** by asking the agent "check my vulcan auth status" — it should call `mcp__vulcan__auth_status` and report your name/email. If you see "tool not found", the MCP server isn't connected.

Full server docs and tool inventory: see the `vulcan-mcp-server` README.

## Before you do anything

1. Call `mcp__vulcan__auth_status` once per session to confirm the user is signed in. If not authenticated, tell the user to sign in to Vulcan in their host app — do not try to work around it.
2. If the user names a project by code (e.g. "VPS", "PROJ"), resolve it with `mcp__vulcan__get_project_by_code` before any work. Never guess `project_id`.
3. If the user references "the current sprint" or "this sprint", resolve via `mcp__vulcan__get_active_sprint` for that project.

## Core flows

### Reporting on activity
- "What's happening today / this week?" → `mcp__vulcan__recent_activity` or `mcp__vulcan__activity_summary` with an ISO date range.
- "What am I working on?" / "my tasks" → `mcp__vulcan__my_activity`, then `mcp__vulcan__list_tasks` filtered to the user.
- "What changed on PROJ?" → `mcp__vulcan__project_activity`.
- "History of TASK-123" → `mcp__vulcan__task_activity` plus `mcp__vulcan__task_work_log`.

### Creating work-items
Vulcan has 6 tiers: **feature → epic → story / bug → task → subtask**. Required fields per tier:
- `feature` — `product_owner_id`, no `parent_id`
- `epic` — `parent_id` (a feature)
- `story` — `parent_id`, `user_story` ("As a [role], I want [goal] so that [benefit]"), `acceptance_criteria`
- `bug` — `parent_id`, `severity` (p0/p1/p2/p3), `steps_to_reproduce`
- `task` — `parent_id`, `assignee_id`
- `subtask` — `parent_id` (a task); sprint is inherited

If the backend returns `{ field, hint }`, surface the hint and ask the user — **do not invent values**. To draft without validation, pass `lifecycle_stage: "draft"`.

### Sprint operations
- Create with `create_sprint` (needs `start_date`, `end_date` as ISO).
- Move tasks in/out with `assign_sprint` (`sprint_id: null` removes).
- `start_sprint` → `complete_sprint` is the lifecycle.
- Only `story`, `bug`, `task` belong in sprints.

### Documents
- List with `list_documents`; fetch with `get_document`.
- Edit with `update_document`; submit for review with `submit_document_for_review`.
- Reviewers use `approve_document` / `reject_document`.
- Common section IDs: `prd`, `roadmap`, `business`, `biz-flow`, `data`, `app`, `tech`, `design`, `adrs`, `specs`, `sys-flow`, `integrations`.

### Comments & links
- `add_comment` anchors to **either** `task_id` **or** (`document_id` + `section_id`) — never both. Use `parent_comment_id` to reply.
- Use `create_external_link` to attach GitHub PRs / Figma / Notion (`system` + `url` required).
- Use `create_task_link` for `blocks` / `blocked_by` / `relates_to` between work-items.

### Bulk grooming
- Use a bulk tool whenever you'd otherwise loop the same op over >2 tasks.
- Hard cap: **100 tasks per call**. If the agent has more, batch.
- `bulk_update_tasks` is the general tool — `updates` is a whitelist (`assignee_id, priority, sprint_id, column_id, type, points, parent_id, severity, acceptance_criteria, affected_versions`).
- `bulk_assign_tasks` and `bulk_move_to_sprint` are sugar over `bulk_update_tasks` — use them for the two most common verbs; pass `sprint_id: null` to **remove** tasks from a sprint.
- `bulk_move_tasks` changes column/status (Kanban move).
- `bulk_delete_tasks` is irreversible — **confirm with the user first**, then call.
- All bulk tools return `{ total, successful, failed, results[] }`. Surface the failures to the user — never silently drop them.

### Reporting (analytics)
Pick the smallest tool that answers the question:
- "How fast is the team?" → `get_velocity` (recent sprints' completed points).
- "Are we on track this sprint?" → `get_burndown` (needs both `project_id` and `sprint_id`).
- "What % of work got done?" → `get_completion_rate` (optional `date_range`).
- "Standup / status digest" → `get_status_summary` (counts by status + blockers + recent changes). Prefer this over hand-rolling from `list_tasks`.
- "Give me the data" → `export_project_data` with `format: "json" | "csv"`. Returns a preview + size; full download stays in the app.

### Profile
- `get_user_profile` defaults to the caller — omit `user_id` to get "my profile".
- `update_user_profile` accepts `{ name?, avatar_url? }` only. Self-only unless caller is an org admin; the backend enforces this.

## Conventions

- **Read before write.** When the user says "update X", fetch with `get_task` / `get_document` first, then patch only the changed fields.
- **Two-step deletes.** `delete_*` tools return a `confirmation_token` first — only echo it back after the user explicitly approves.
- **Names, not IDs, to the user.** Resolve IDs to titles/codes when summarizing. Show the work-item key (e.g. `VPS-142`) when available.
- **Dates are ISO.** Convert relative dates ("Friday", "next sprint") to absolute ISO strings before calling tools.
- **Don't fan out for trivial reads.** A single `list_tasks` with the right filter beats five `get_task` calls.

## When NOT to use Hermes

- Editing source code in this repo → use normal coding tools.
- Driving GitHub PRs directly → use `gh`.
- Generic project management questions unrelated to a Vulcan instance.

## Quick recipes

**"Show me today's standup"**
1. `get_active_sprint(project_id)`
2. `list_tasks({ sprint_id, assignee_id: <me> })`
3. `my_activity({ from: <today 00:00>, to: <now> })`
4. Summarize: in-progress, blocked (look for `blocked_by` links), done since yesterday.

**"File a bug from this error"**
1. Resolve project → `get_project_by_code`.
2. Pick parent story/epic with `list_tasks` filtered by type.
3. `create_task({ type: "bug", parent_id, severity, steps_to_reproduce, ... })`.
4. Optionally `create_external_link` to the failing CI run.

**"Approve the PRD on PROJ"**
1. `get_document({ project_id, section_id: "prd" })` — confirm contents.
2. `list_pending_document_reviews` to ensure it's awaiting you.
3. `approve_document({ section_id, note })`.

**"Move all p2 bugs out of the current sprint on PROJ"**
1. `get_project_by_code({ code: "PROJ" })` → `project_id`.
2. `get_active_sprint({ project_id })` → `sprint_id`.
3. `list_tasks({ project_id, sprint_id, type: "bug", severity: "p2" })` → collect task IDs.
4. `bulk_move_to_sprint({ task_ids, sprint_id: null })`.
5. Summarize the `successful` / `failed` counts back to the user.

**"What's the standup for PROJ?"**
1. `get_active_sprint({ project_id })`.
2. `get_status_summary({ project_id, sprint_id })` — counts, blockers, recent changes in one call.
3. `my_activity` filtered to last 24h for what the *caller* changed.
4. Render: in-progress, blocked, done since yesterday.
