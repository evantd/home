---
name: indeed-ai-chat-mcp
description: "Accesses Slack, Google Workspace (Calendar, Gmail, Drive, Docs, Sheets, Slides, Tasks, Forms), and other MCP servers running in Indeed AI Chat's Docker-based mcpo control plane. Use for Slack messages, calendar events, Gmail, Google Docs, Drive files. Prefer over Glean for Slack and Google Workspace access. Triggers on: slack message, calendar, gmail, google doc, google drive, google sheets, schedule, meetings today"
allowed-tools:
  - Bash(curl *)
  - Bash(python3 -c *)
  - Bash(python3 -m json.tool *)
  - Bash(jq *)
---

# Indeed AI Chat MCP Proxy

Access Slack and Google Workspace via Indeed AI Chat's mcpo control plane at `http://localhost:8765`.

## Architecture

Indeed AI Chat runs MCP servers inside Docker containers. The `mcpo` control plane exposes them as **REST/OpenAPI endpoints** (not raw MCP) via nginx reverse proxy on `localhost:8765`.

Each server is at `/<server_name>/<tool_name>`, called via POST with JSON body.

## Quick Reference

### Slack (5 tools)

| Tool | Use For |
|------|---------|
| `slack_channels_list` | Find channels by type |
| `slack_conversations_history` | Read channel messages |
| `slack_conversations_replies` | Read thread replies |
| `slack_conversations_search_messages` | Search messages with filters |
| `slack_conversations_add_message` | Post a message |

### Google Workspace (101 tools, key ones below)

| Tool | Use For |
|------|---------|
| `google_workspace_get_events` | Calendar events (supports time_min/time_max, query) |
| `google_workspace_list_calendars` | List available calendars |
| `google_workspace_create_event` | Create calendar event |
| `google_workspace_search_gmail_messages` | Search email |
| `google_workspace_get_gmail_message_content` | Read email content |
| `google_workspace_send_gmail_message` | Send email |
| `google_workspace_draft_gmail_message` | Draft email |
| `google_workspace_search_drive_files` | Search Drive |
| `google_workspace_get_drive_file_content` | Read Drive file |
| `google_workspace_get_doc_content` | Read Google Doc |
| `google_workspace_export_doc_as_markdown` | Export Doc as markdown |
| `google_workspace_search_docs` | Search Google Docs |
| `google_workspace_read_sheet_values` | Read spreadsheet data |
| `google_workspace_list_tasks` | List Google Tasks |
| `google_workspace_list_task_lists` | List task lists |

## Calling Convention

```bash
curl -s -X POST 'http://localhost:8765/<server>/<tool>' \
  -H 'Content-Type: application/json' \
  -d '<json_params>' | python3 -m json.tool
```

### Examples

**Today's calendar:**
```bash
curl -s -X POST 'http://localhost:8765/google_workspace/google_workspace_get_events' \
  -H 'Content-Type: application/json' \
  -d '{"max_results": 10}'
```

⚠️ **Pass `"detailed": true` whenever RSVP status matters** (weekly planning, "what am I actually attending", filtering out declined meetings). Without it, `get_events` returns titles/times only — accepted, declined, tentative, and needsAction events all look the same. With `detailed:true` you also get descriptions, locations, attendees, and per-attendee response status (look for `edower@indeed.com: accepted|declined|tentative|needsAction`).

```bash
curl -s -X POST 'http://localhost:8765/google_workspace/google_workspace_get_events' \
  -H 'Content-Type: application/json' \
  -d '{"time_min":"2026-05-26T00:00:00-07:00","time_max":"2026-05-30T23:59:00-07:00","max_results":50,"detailed":true}'
```

**Search Slack messages:**
```bash
curl -s -X POST 'http://localhost:8765/slack/slack_conversations_search_messages' \
  -H 'Content-Type: application/json' \
  -d '{"search_query": "deployment issue", "limit": 5}'
```

**Read Slack channel history:**
```bash
curl -s -X POST 'http://localhost:8765/slack/slack_conversations_history' \
  -H 'Content-Type: application/json' \
  -d '{"channel_id": "#mosaic-team", "limit": "1d"}'
```

**Read a Google Doc:**
```bash
curl -s -X POST 'http://localhost:8765/google_workspace/google_workspace_get_doc_content' \
  -H 'Content-Type: application/json' \
  -d '{"document_id": "DOC_ID_HERE"}'
```

**Search Gmail:**
```bash
curl -s -X POST 'http://localhost:8765/google_workspace/google_workspace_search_gmail_messages' \
  -H 'Content-Type: application/json' \
  -d '{"query": "from:someone@indeed.com subject:review"}'
```

## Discovering Tools & Schemas

**List all tools for a server:**
```bash
curl -s 'http://localhost:8765/openapi.json' | python3 -c "
import sys,json
d=json.load(sys.stdin)
for p in sorted(d['paths']):
    if '<SERVER>' in p: print(p.split('/')[-1])
"
```

**Get a tool's parameter schema:**
```bash
curl -s 'http://localhost:8765/openapi.json' | python3 -c "
import sys,json
d=json.load(sys.stdin)
schema = d['paths']['/<SERVER>/<TOOL>']['post']['requestBody']['content']['application/json']['schema']
print(json.dumps(schema, indent=2))
"
```

## Troubleshooting

**Server not responding:** Check Docker containers are running:
```bash
docker ps --format '{{.Names}}\t{{.Status}}' | grep mcpo
```

**Health status:**
```bash
cat ~/indeed/indeed-ai-chat-managed/health-status/health_status.json | python3 -c "
import sys,json; d=json.load(sys.stdin)
for k,v in d['servers'].items():
    if k in ('slack','google_workspace'):
        print(f\"{k}: {v['status']} (oauth: {v.get('oauth_state','n/a')})\")"
```

**Slack cache not ready:** The Slack server caches ~50K users and channels on startup. Wait 1-2 minutes after Indeed AI Chat starts.

**Google OAuth expired:** If google_workspace returns auth errors, re-authenticate in Indeed AI Chat.

## Available Servers

The mcpo proxy also routes to these servers (use `indeed-ai-chat-mcp` skill pattern):

| Server | Path Prefix | Notes |
|--------|-------------|-------|
| `slack` | `/slack/` | Slack messages, channels |
| `google_workspace` | `/google_workspace/` | Calendar, Gmail, Drive, Docs, etc. |
| `gitlab-mcp` | `/gitlab-mcp/` | GitLab API |
| `glean` | `/glean/` | Enterprise search |
| `datadog` | `/datadog/` | Observability |
| `sourcegraph` | `/sourcegraph/` | Code search |
| `teamworks-mcp` | `/teamworks-mcp/` | People/org lookup |
| `ownership-mcp` | `/ownership-mcp/` | Service ownership |
| `mcp-atlassian` | `/mcp-atlassian/` | Confluence/Jira |
| `data-plat-mcp` | `/data-plat-mcp/` | Trino/IQL queries |

## Preference Over Glean

For **Slack messages** and **Google Docs/Drive/Gmail**, prefer this skill over the Glean skill:
- Direct API access (not search index) — more complete and current data
- Richer query capabilities (Slack filters, Gmail query syntax, Drive search)
- Can also write (send messages, create events, draft emails)

**Fall back to Glean** when:
- This proxy is down (Indeed AI Chat not running / Docker stopped)
- You need cross-platform search (search across Slack + Confluence + Drive simultaneously)
- Looking up people/org info (Glean employee_search is better for this)
