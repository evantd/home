# Atlassian CLI (`acli`) Instructions

When the Atlassian MCP server is unavailable, use `acli` to interact with Jira and (limited) Confluence.

**Prerequisites:**
- `acli` installed (`brew tap atlassian/homebrew-acli && brew install acli`)
- Authenticated: `acli jira auth login` and `acli confluence auth login --web`
- Jira and Confluence require **separate** auth. Jira uses API token; Confluence requires OAuth (`--web`).

## Common Commands

### Jira

**List Issues:**
```bash
acli jira workitem search --jql "assignee = currentUser()"
```

**View Issue:**
```bash
acli jira workitem view <issue-key>
```

**Transition Issue:**
```bash
acli jira workitem transition <issue-key> --transition <transition-name>
```

**Add Comment:**
```bash
acli jira workitem comment create <issue-key> --body "<comment>"
```

### Create Issue

Use `--from-json` with a JSON file. Work item types:
- `Task` — No code changes (investigations, config, process)
- `Improvement` — Enhancement to existing functionality (default if unclear)
- `New Feature` — Brand new functionality
- `Bug` — Fixing broken behavior

```json
{
  "projectKey": "PROJ",
  "type": "Improvement",
  "summary": "Short title under 100 chars",
  "parentIssueId": "PROJ-123",
  "description": { ... }
}
```

```bash
acli jira workitem create --from-json /tmp/jira-ticket.json
```

**⚠️ Do NOT use the `--parent` CLI flag** — it silently fails. Always use `parentIssueId` in the JSON file instead.

`parentIssueId` uses the issue **key** (e.g., `PROJ-123`), not numeric ID. It respects Jira hierarchy: Sub-task → Issue, Issue → Epic.

### Create Sub-task

```json
{
  "projectKey": "PROJ",
  "type": "Sub-task",
  "parentIssueId": "PROJ-123",
  "summary": "Sub-task title",
  "description": { ... }
}
```

### Find Parent Epic

```bash
acli jira workitem search --jql "project = PROJ AND issuetype = Epic AND status not in (Done, Closed) ORDER BY updated DESC" --fields "key,summary,status" --limit 30
```

## Formatting Issue Descriptions with ADF

**Problem**: `acli jira workitem edit --description` treats input as plain text. Markdown syntax appears literally (e.g., `## Summary` instead of a heading).

**Solution**: Use `--from-json` with a properly structured payload containing ADF.

### Setup

```bash
npm install -g marklassian
```

### Usage Pattern

```bash
# 1. Create markdown file
cat > /tmp/description.md << 'EOF'
## Summary
- Point 1
- Point 2
EOF

# 2. Convert to ADF and wrap in acli payload format
NODE_PATH=$(npm root -g) node -e "
const {markdownToAdf} = require('marklassian');
const fs = require('fs');
const md = fs.readFileSync('/tmp/description.md', 'utf8');
const adf = markdownToAdf(md);
const payload = { 
  issues: ['ISSUE-123'],
  description: adf 
};
fs.writeFileSync('/tmp/payload.json', JSON.stringify(payload, null, 2));
"

# 3. Update Jira
acli jira workitem edit --from-json /tmp/payload.json --json --yes
```

### Key Points

- **Do NOT use `--key` with `--from-json`** — they're mutually exclusive
- **Do NOT pass raw ADF to `--description` or `--description-file`** — it won't parse correctly
- The payload format must be: `{ "issues": ["KEY-1"], "description": <ADF object> }`
- Supported `--from-json` edit fields: `issues` (required), `description`, `summary`, `assignee`, `type`, `labelsToAdd`, `labelsToRemove`
- Use `acli jira workitem edit --generate-json` to see the expected schema
- Add `--yes` to skip confirmation prompt
- **Edit summary only** (no ADF needed): `acli jira workitem edit --key "KEY-1" --summary "new title" --yes`
- **Changing parent epic on edit** is not supported by `acli` — must use Jira UI

### ADF Gotchas

- **Never combine `code` + `strong` marks** on the same text node — causes `INVALID_INPUT` error
- **`codeBlock`**: Do NOT include `attrs.language` — it may cause errors
- If you need bold code-like text, use just `code` or just `strong`, not both

## Confluence (v1.3.18 — limited support)

**What works:**
- `acli confluence page view --id <pageID>` — read a page by ID (requires knowing the ID)
  - Add `--body-format storage` for XHTML or `--body-format atlas_doc_format` for ADF
  - Add `--json` for structured output
- `acli confluence space list` — list spaces (but `--keys` filter is **broken**, ignores the filter)
- `acli confluence space view --id <spaceID>` — view space details
- `acli confluence blog list --space-id <id>` — list blog posts
- `acli confluence blog create` — create blog posts

**What's missing:**
- **No page search** — can't find pages by title or CQL query
- **No page list** — can't list pages within a space
- **No page create/edit/delete** — read-only for pages
- **No search at all** — no CQL or full-text search equivalent

**When to use Confluence via acli (even if MCP is available):**
- **Blog posts** — acli can list, view, and create blog posts; the Atlassian MCP has no blog support
- Reading a specific page when MCP is down (if you already have the page ID)
- Listing spaces

**When to use the Atlassian MCP skill instead:**
- Searching for pages (CQL queries)
- Finding pages by title + space key
- Creating, editing, deleting, or moving pages
- Comments, labels, attachments, page history/diffs
- The MCP has 72 tools total (full Confluence + Jira CRUD); the skill only documents 3 — run `tools/list` to discover more

## When to use
- Checking ticket status
- Transitioning tickets (e.g. moving to "In Progress")
- Adding comments/updates when MCP is flaky
- Reading a known Confluence page by ID when MCP is down
- Prefer CLI over MCP when both work (CLIs are more reliable and use less context)
