---
name: atlassian
description: Interacts with Atlassian Confluence and Jira via MCP server (toolhive) and acli CLI. Use for Confluence pages, wiki search, Jira issues, and blog posts. Always use this instead of read_web_page for Atlassian URLs (indeed.atlassian.net) — they require auth.
metadata:
  claude:
    context: fork
    agent: general-purpose
allowed-tools:
  - Bash(thv list *)
  - Bash(thv run atlassian *)
  - Bash(curl * 127.0.0.1:* *)
  - Bash(mcpc --config * atlassian tools-call *)
  - Bash(mcpc --config * atlassian tools-list *)
  - Bash(jq *)
  - Bash(acli *)
---

# Atlassian (MCP + acli CLI)

Two interfaces to Atlassian. Use the right one for the job:

| Capability | MCP (toolhive) | acli CLI |
|---|---|---|
| **Confluence pages** — search, read, create, edit, delete, move | ✅ Full CRUD (72 tools) | ⚠️ Read-only by page ID |
| **Confluence blogs** — list, view, create | ❌ None | ✅ |
| **Confluence spaces** — list, view, create | ✅ | ✅ (but `--keys` filter broken) |
| **Confluence comments, labels, attachments** | ✅ | ❌ |
| **Confluence page history/diffs** | ✅ | ❌ |
| **Jira issues** — search, CRUD, transitions | ✅ Full CRUD | ✅ Full CRUD |
| **Jira sprints, boards, versions** | ✅ | ❌ |

**Default to MCP** for most operations. Use **acli** for blog posts, or as a fallback when MCP is down.

## Auth

| Interface | Auth method | Command |
|---|---|---|
| MCP | Managed by toolhive | `thv run atlassian` (auto) |
| acli Jira | API token | `acli jira auth login` |
| acli Confluence | OAuth (browser) | `acli confluence auth login --web` |

Jira and Confluence acli auth are **separate** — you need both if using acli for both products.

---

## MCP Server (Primary)

### Setup

```bash
# Start server (if not running)
thv run atlassian

# Discover URL (port is dynamic)
thv list --format json 2>/dev/null | python3 -c "import sys,json; [print(s['url']) for s in json.load(sys.stdin) if s['name']=='atlassian']"
```

### Calling Tools

**Using mcpc** (preferred):
```bash
mcpc --config assets/mcpc.json atlassian tools-call <tool> <params>
```

> **Note:** The port in `assets/mcpc.json` may need updating if the server has restarted. Run the discovery command above and update the port if mcpc fails to connect.

**Using curl directly:**
```bash
ATLASSIAN_URL=$(thv list --format json 2>/dev/null | python3 -c "import sys,json; [print(s['url']) for s in json.load(sys.stdin) if s['name']=='atlassian']")

curl -s -X POST "$ATLASSIAN_URL" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"confluence_get_page","arguments":{"page_id":"12345"}}}' | jq .
```

### Discovering Tools

The MCP server has ~72 tools. Don't guess — list them:
```bash
mcpc --config assets/mcpc.json atlassian tools-list
```

### Common MCP Workflows

**Read a Confluence page by URL:**
```bash
# URL: https://indeed.atlassian.net/wiki/spaces/MAP/pages/123456789/My+Page
# → page_id is 123456789
mcpc --config assets/mcpc.json atlassian tools-call confluence_get_page page_id:="123456789"
```

**Read a page by title + space:**
```bash
mcpc --config assets/mcpc.json atlassian tools-call confluence_get_page title:="My Page" space_key:="MAP"
```

**Search Confluence (CQL):**
```bash
mcpc --config assets/mcpc.json atlassian tools-call confluence_search query:="text ~ \"mosaic provider\" AND space = MAP"
```

**Create a Confluence page:**
```bash
mcpc --config assets/mcpc.json atlassian tools-call confluence_create_page space_key:="MAP" title:="New Page" body:="<p>Content</p>" parent_id:="123456789"
```

**Get a Jira issue:**
```bash
mcpc --config assets/mcpc.json atlassian tools-call jira_get_issue issue_key:="MAP-42"
```

**Search Jira (JQL):**
```bash
mcpc --config assets/mcpc.json atlassian tools-call jira_search jql:="assignee = currentUser() AND status != Done"
```

### Key MCP Tool Categories

**Confluence:** `confluence_get_page`, `confluence_search`, `confluence_create_page`, `confluence_update_page`, `confluence_delete_page`, `confluence_move_page`, `confluence_get_page_children`, `confluence_get_page_history`, `confluence_get_page_diff`, `confluence_add_comment`, `confluence_get_comments`, `confluence_add_label`, `confluence_get_labels`, `confluence_upload_attachment`, `confluence_get_attachments`

**Jira:** `jira_get_issue`, `jira_search`, `jira_create_issue`, `jira_update_issue`, `jira_delete_issue`, `jira_add_comment`, `jira_transition_issue`, `jira_get_transitions`, `jira_link_to_epic`, `jira_create_issue_link`, `jira_get_sprints_from_board`, `jira_get_sprint_issues`

### MCP Troubleshooting

| Problem | Fix |
|---------|-----|
| `Connection refused` | Server not running — `thv run atlassian` |
| `Connection refused` after restart | Port changed — rediscover with `thv list` and update `assets/mcpc.json` |
| Server not in `thv list` | Start it: `thv run atlassian` |
| `ENOTFOUND atlassian` with mcpc | Missing `--config assets/mcpc.json` |

---

## acli CLI (Fallback + Blogs)

**Prerequisites:**
- `acli` installed (`brew tap atlassian/homebrew-acli && brew install acli`)
- Auth status: `acli jira auth status` / `acli confluence auth status`

### Jira via acli

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

**Create Issue** (use `--from-json`):

Work item types: `Task`, `Improvement`, `New Feature`, `Bug`, `Sub-task`

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

**⚠️ Do NOT use the `--parent` CLI flag** — it silently fails. Always use `parentIssueId` in the JSON file.

`parentIssueId` uses the issue **key** (e.g., `PROJ-123`), not numeric ID.

**Find Parent Epic:**
```bash
acli jira workitem search --jql "project = PROJ AND issuetype = Epic AND status not in (Done, Closed) ORDER BY updated DESC" --fields "key,summary,status" --limit 30
```

### Confluence via acli (limited — v1.3.18)

**Read a page by ID:**
```bash
acli confluence page view --id <pageID> --body-format storage --json
# body-format options: storage (XHTML), atlas_doc_format (ADF), view
```

**List/view spaces:**
```bash
acli confluence space list --limit 10
acli confluence space view --id <spaceID>
```

**Blog posts** (acli-only capability):
```bash
acli confluence blog list --space-id <id> --limit 10
acli confluence blog view --id <blogID>
acli confluence blog create --space-id <id> --title "Title" --body "<p>Content</p>"
acli confluence blog create --from-file ./content.html --space-id <id> --title "Title"
```

**What's missing from acli Confluence:**
- No page search, list, create, edit, or delete
- No CQL or full-text search
- `space list --keys` filter is broken (ignores the filter)

### ADF Formatting for Jira (acli)

`acli jira workitem edit --description` treats input as **plain text**. For rich formatting, use `--from-json` with ADF:

```bash
# Install converter
npm install -g marklassian

# Convert markdown → ADF → acli payload
NODE_PATH=$(npm root -g) node -e "
const {markdownToAdf} = require('marklassian');
const fs = require('fs');
const md = fs.readFileSync('/tmp/description.md', 'utf8');
const adf = markdownToAdf(md);
const payload = { issues: ['ISSUE-123'], description: adf };
fs.writeFileSync('/tmp/payload.json', JSON.stringify(payload, null, 2));
"

# Update Jira
acli jira workitem edit --from-json /tmp/payload.json --json --yes
```

**Key points:**
- Do NOT use `--key` with `--from-json` — mutually exclusive
- Do NOT pass raw ADF to `--description` or `--description-file`
- Payload format: `{ "issues": ["KEY-1"], "description": <ADF object> }`
- Supported edit fields: `issues` (required), `description`, `summary`, `assignee`, `type`, `labelsToAdd`, `labelsToRemove`
- **Edit summary only** (no ADF needed): `acli jira workitem edit --key "KEY-1" --summary "new title" --yes`
- **Changing parent epic on edit** is not supported — must use Jira UI

**ADF gotchas:**
- **Never combine `code` + `strong` marks** on the same text node — causes `INVALID_INPUT`
- **`codeBlock`**: Do NOT include `attrs.language` — may cause errors
