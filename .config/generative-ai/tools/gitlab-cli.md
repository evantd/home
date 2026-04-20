# GitLab CLI (`glab`) Instructions

When the GitLab MCP server is unavailable or you need to perform operations directly from the terminal, use `glab`.

**Prerequisites:**
- `glab` installed (`brew install glab`)
- Authenticated (`glab auth login`)

**Host resolution:**
- Most commands (`mr`, `ci`, `issue`, etc.) auto-detect the GitLab host from the repo's git remote. Do NOT pass `--hostname` to these commands.
- Only `glab api` requires `--hostname <host>` when targeting a non-default instance (e.g., `--hostname code.corp.indeed.com`).

## Common Commands

### Merge Requests

**Create a Merge Request:**
```bash
glab mr create \
  --source-branch <branch-name> \
  --target-branch main \
  --title "<title>" \
  --description "<description>" \
  --squash-before-merge \
  --remove-source-branch \
  --yes
```

**List Merge Requests:**
```bash
glab mr list
```

**View specific MR:**
```bash
glab mr view <id>
```

### Issues

**List Issues:**
```bash
glab issue list
```

**Create Issue:**
```bash
glab issue create --title "<title>" --description "<description>"
```

### Viewing MR Comments

**Top-level comments:**
```bash
glab mr view <id> --comments
```

**Inline diff comments** (code review comments on specific lines):
```bash
glab api "/projects/<url-encoded-project>/merge_requests/<id>/discussions" --paginate | jq -r '.[] | select(.notes[0].type == "DiffNote") | .notes[] | "File: \(.position.new_path):\(.position.new_line // "N/A")\n\(.author.username): \(.body)\n---"'
```

Example for globalnav-render-service MR 3852:
```bash
glab api "/projects/frontend%2Fglobalnav-render-service/merge_requests/3852/discussions" --paginate | jq -r '.[] | select(.notes[0].type == "DiffNote") | .notes[] | "File: \(.position.new_path):\(.position.new_line // "N/A")\n\(.author.username): \(.body)\n---"'
```

**Important**: `glab mr view --comments` only shows top-level comments, not inline diff discussions.

**⚠️ Pagination**: Always use `--paginate` with `glab api` for any list endpoint (discussions, notes, pipelines, etc.). GitLab's API is notorious for returning short pages even when more results exist — never assume a partial page means you've reached the end. Without `--paginate`, you will silently miss results.

### Creating MR Comments

**General (non-diff) comment:**
```bash
glab mr note <id> --message "comment text"
```

**Diff note (inline comment on a specific line):**

Use `glab api` with `--input` and `-H "Content-Type: application/json"` to POST a JSON body containing the `position` object. You need the MR's `diff_refs` (get them from `glab mr view <id>` or the API).

> **⚠️ Do NOT use `--raw-field 'position[...]=...'` for diff notes** — `glab` does not properly serialize nested bracket-notation fields into the `position` object. The result is a top-level discussion comment with `position: null` instead of an inline diff note. Always use `--input` with a JSON file.

```bash
# 1. Get diff_refs for the MR
glab api "/projects/<url-encoded-project>/merge_requests/<id>" | jq '.diff_refs'

# 2. Write the JSON payload to a file (use jq, python, etc.)
#    - body: the comment text (supports markdown, GitLab suggestions)
#    - new_line: integer line number in the NEW version of the file
cat > /tmp/diff-note.json << 'EOF'
{
  "body": "Your comment here",
  "position": {
    "base_sha": "<base_sha>",
    "head_sha": "<head_sha>",
    "start_sha": "<start_sha>",
    "position_type": "text",
    "old_path": "path/to/file.ts",
    "new_path": "path/to/file.ts",
    "new_line": 42
  }
}
EOF

# 3. Post the diff note
glab api "/projects/<url-encoded-project>/merge_requests/<id>/discussions" \
  --method POST \
  -H "Content-Type: application/json" \
  --input /tmp/diff-note.json
```

**For comment bodies with special characters** (backticks, quotes, unicode), generate the JSON payload with `jq` or `python` to handle escaping:

```bash
# Write body to a text file, then build JSON with jq
cat > /tmp/comment-body.txt << 'EOF'
Your comment with `backticks` and **markdown**

```suggestion:-0+0
replacement code here
```
EOF

python3 -c "
import json
body = open('/tmp/comment-body.txt').read()
json.dump({
    'body': body,
    'position': {
        'base_sha': '<base_sha>',
        'head_sha': '<head_sha>',
        'start_sha': '<start_sha>',
        'position_type': 'text',
        'old_path': 'path/to/file.ts',
        'new_path': 'path/to/file.ts',
        'new_line': 42
    }
}, open('/tmp/diff-note.json', 'w'))
"

glab api "/projects/<url-encoded-project>/merge_requests/<id>/discussions" \
  --method POST \
  -H "Content-Type: application/json" \
  --input /tmp/diff-note.json
```

**Key parameters:**
- `new_line` — integer line number in the new file (for added/changed lines)
- `old_line` — integer line number in the old file (for deleted lines)
- `old_path` / `new_path` — use the same value unless the file was renamed
- The response `type` should be `"DiffNote"` — if you get `"DiscussionNote"` with `position: null`, the position wasn't sent correctly
- For **GitLab suggestions**, use fenced code blocks with `suggestion` language in the body:
  ````
  ```suggestion:-0+0
  replacement code here
  ```
  ````
  The `-0+0` means "replace 0 lines above and 0 lines below the commented line." For multi-line suggestions, use `suggestion:-N+M` where N covers lines above and M covers lines below the commented line.

**Reply to an existing discussion thread:**
```bash
glab api "/projects/<url-encoded-project>/merge_requests/<id>/discussions/<discussion_id>/notes" \
  --method POST \
  --raw-field 'body=Reply text'
```

## When to use
- Creating MRs (especially when MCP fails)
- Checking CI/CD status (`glab ci status`)
- Viewing pipeline logs (`glab ci trace`)
- Retrieving inline code review comments from MRs
- Posting diff comments / code review feedback on MRs
- Reading file contents from repos without cloning

## Reading File Contents

**Get raw file content from a remote repository:**
```bash
glab api '/projects/<url-encoded-project>/repository/files/<url-encoded-path>/raw?ref=<branch>' --hostname <gitlab-host>
```

**Example:** Read `tea_analytics/data_sources/DataSource.py` from branch `hackathon/seth`:
```bash
glab api '/projects/edower%2Ftalent-enablement-automation/repository/files/tea_analytics%2Fdata_sources%2FDataSource.py/raw?ref=hackathon%2Fseth' --hostname code.corp.indeed.com
```

**Key points:**
- URL-encode the project path (`/` → `%2F`)
- URL-encode the file path (`/` → `%2F`)
- URL-encode the branch name (`/` → `%2F`)
- Use `--hostname` for Indeed GitLab (`code.corp.indeed.com`)

**Browse repository tree:**
```bash
glab api '/projects/<url-encoded-project>/repository/tree?ref=<branch>&path=<optional-path>' --hostname <host>
```

**Alternative (if you have repo cloned locally):**
```bash
git fetch origin <branch>
git show origin/<branch>:<path/to/file>
```
This is often simpler if you already have the repo cloned.
