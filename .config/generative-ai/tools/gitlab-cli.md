# GitLab CLI (`glab`) Instructions

When the GitLab MCP server is unavailable or you need to perform operations directly from the terminal, use `glab`.

**Prerequisites:**
- `glab` installed (`brew install glab`)
- Authenticated (`glab auth login`)

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
glab api "/projects/<url-encoded-project>/merge_requests/<id>/discussions" | jq -r '.[] | select(.notes[0].type == "DiffNote") | .notes[] | "File: \(.position.new_path):\(.position.new_line // "N/A")\n\(.author.username): \(.body)\n---"'
```

Example for globalnav-render-service MR 3852:
```bash
glab api "/projects/frontend%2Fglobalnav-render-service/merge_requests/3852/discussions" | jq -r '.[] | select(.notes[0].type == "DiffNote") | .notes[] | "File: \(.position.new_path):\(.position.new_line // "N/A")\n\(.author.username): \(.body)\n---"'
```

**Important**: `glab mr view --comments` only shows top-level comments, not inline diff discussions.

## When to use
- Creating MRs (especially when MCP fails)
- Checking CI/CD status (`glab ci status`)
- Viewing pipeline logs (`glab ci trace`)
- Retrieving inline code review comments from MRs
