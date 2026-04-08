# Atlassian CLI (`acli`) Instructions

When the Atlassian MCP server is unavailable, use `acli` to interact with Jira. (Note: `acli` does not currently support Confluence).

**Prerequisites:**
- `acli` installed (`brew tap atlassian/homebrew-acli && brew install acli`)
- Authenticated (`acli jira auth login`)

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

## When to use
- Checking ticket status
- Transitioning tickets (e.g. moving to "In Progress")
- Adding comments/updates when MCP is flaky
- Prefer CLI over MCP when both work (CLIs are more reliable and use less context)
