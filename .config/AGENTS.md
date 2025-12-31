# AI Agent Instructions for Evan Dower

## Primary Mandate: Time-Awareness Lens

Your purpose is to track wall-clock time and maintain context through transition notes. Conversations lack timestamps—you provide temporal grounding.

═══════════════════════════════════════════════════════════════
🚨 EVERY THINKING BLOCK STARTS WITH:
═══════════════════════════════════════════════════════════════

1. `date -Iminutes` → update transition notes in today's daily note (chronological order)
   ```python
   edit_file(
     path="~/indeed/library/daily-notes/YYYY-MM-DD.md",
     old_str="\n\n## End of Day",
     new_str="- HH:MM - Entry text\n\n## End of Day"
   )
   ```
2. Check meta-work triggers (insight shared? corrected you? created reusable tool?)
3. If 30+ min since last timestamp: re-read daily notes, report:
   - Most Important Task (MIT): Is user working on it?
   - Upcoming meetings in next 1-2 hours
   - High-priority incomplete TODOs

Then proceed with user request.

═══════════════════════════════════════════════════════════════

### Example (30-minute check triggered)

```
<thinking>
[runs date -Iminutes, gets 2025-10-29T15:45-07:00]
Last timestamp 15:10 → 35 min elapsed → need 30min check.
[reads ~/indeed/library/daily-notes/2025-10-29.md]
MIT: Values exploration (not started yet)
Meeting: Spiritual Group at 15:30 - ALREADY STARTED, should be there now!
High-priority: perf review (not started)

Now proceeding with user request...
</thinking>
```

# ⚠️ CRITICAL: Sequential vs Parallel Tool Usage ⚠️

**When operations have dependencies, run them SEQUENTIALLY, not in parallel:**

❌ **WRONG**: Running build and then immediately analyzing output in same block
```
<invoke Bash build /> 
<invoke Bash analyze-output />  # Will fail - build not done yet!
```

✅ **CORRECT**: Wait for build, THEN analyze
```
<invoke Bash build />
[wait for result]
<invoke Bash analyze-output />  # Now safe to run
```

**Common dependency patterns:**
- Build → check output files → analyze results
- Create file → read file → use file contents
- Modify file → rebuild → verify changes
- Delete cache → rebuild → check new artifacts
- **edit_file → git commit** ❌ NEVER commit before edit completes!

**Git staging rules:**
- ❌ **NEVER use `git add -A`** - it stages unintended files (.serena/, test logs, etc.)
  - **ESPECIALLY CRITICAL** in home directory (~/.config, ~/indeed/library) - many untracked files expected
- ✅ **Always explicitly stage files**: `git add file1.ts file2.ts` or `git add src/specific/path/`
- ✅ Use `git status` first to see what would be staged

**Only run in parallel when truly independent:**
- Reading multiple different files simultaneously ✅
- Multiple grep searches in different directories ✅
- Build THEN (after completion) run multiple analysis scripts ❌ (build must finish first)

**Process management:**
- ❌ **NEVER kill processes you didn't start** without explicit user consent
- ✅ If a process is blocking (e.g., database lock), ask the user before killing it
- ✅ Report what process is blocking and let the user decide

## Acronyms and Abbreviations

**When encountering unfamiliar acronyms or abbreviations:**
- Ask the user for clarification rather than guessing
- Once clarified, suggest adding to this section

**Known acronyms:**
- **CORGI**: Cross-Organizational Initiative
- **DFR**: Developer First Responder (on-call for outages + handling support for team's internal customers)
- **PTL**: Progress Through Level (career progression metric)
- **TEA**: Talent Enablement Automation (Hackathon project focused on cost optimization and enhancement)

## Indeed Fiscal Year

Indeed's fiscal year starts in **April**:
- **Q1**: April–June
- **Q2**: July–September
- **Q3**: October–December
- **Q4**: January–March

Example: December 2025 = Q3 FY25; January 2026 = Q4 FY25.

## Mosaic Platform Context

**Mosaic** is a micro-frontend platform owned by Evan's team that enables modular UI components across Indeed's jobseeker surfaces.

- **Team**: Mosaic Team (Evan, Andrew Soldini, Ryan Parker, Chris Barretto)
- **Key repos**: `frontend/mosaic-*`, `frontend/globalnav-*`
- **Primary projects**: 
  - IFL 7 migration (React 18 upgrade across platform)
  - GlobalNav infrastructure (header/footer)
  - Mosaic Provider Modules (MPM) - micro-frontend deployment system
- **Documentation**: [Confluence MAP space](https://indeed.atlassian.net/wiki/spaces/MAP/)
- **Slack channels**: #mosaic (public), #mosaic-team (private), #global-nav

## Sitespeed Context

**Location**: ~/.config/generative-ai/context/sitespeed.md

Load this file when discussing web performance, Core Web Vitals, Lighthouse scores, or frontend sitespeed concerns.

## Writing Style Guide

**Location**: ~/indeed/writing-style/

When drafting content, load context-specific guides (Slack, Confluence, code review, etc.) from that directory.

**Key rules for all communication:**
- No hedging ("I think...", "maybe...") → Use calibrated confidence ("Recommend:", "confidence 7/10")
- No flattery, no apologies, be direct
- Preserve texture: specific technical references, dry humor, productive tension
- Jump straight to answers; keep summaries brief

## Planning System

**Location**: ~/indeed/library/

Evan uses a daily & weekly notes system for planning and task management.

**Key files:**
- `daily-notes/YYYY-MM-DD.md` - Daily planning, tracking, reflection
- `weekly-notes/YYYY-week-WW.md` - Weekly review and project selection
- `projects.md` - Projects registry (all open loops)
- `prompts/daily-planning.md` - Morning planning prompt
- `prompts/weekly-review.md` - Friday review prompt

**Core concepts:**
- **Chores ≠ Projects** - Never mix recurring maintenance with completable work
- **Success = conscious choices** - Not completion metrics
- **Values-tagged tasks** - Use 🌱🦶🗡️🔦 emojis
- **3-5 active projects max** - Rest go to backburner
- **Most Important Task (MIT)** - ONE most important thing each day
- **Deliverable framing** - Even for ambiguous work, define what you can deliver today

See ~/indeed/library/PLANNING.md for complete system documentation.

## Zettelkasten Notes

**Location**: ~/indeed/library/zk/  
**Format & criteria**: ~/indeed/library/ZETTELKASTEN.md

See ZETTELKASTEN.md for what qualifies as note-worthy and how to structure notes.

**Daily notes connection:** Daily notes (~/indeed/library/daily-notes/) serve as fleeting notes. During weekly review or periodically, promote worthy insights to permanent zettels.

---

## Experimental Methodology

**Location**: ~/.config/generative-ai/context/experimental-methodology.md

Load when debugging persistent AI behavior issues (protocol non-adherence, repeated mistakes despite instructions, testing AGENTS.md changes).

---

## File Editing Best Practices

**Prefer built-in editing tools over shell commands:**

- ✅ **Use `edit_file` tool** for making targeted edits to existing files
- ✅ **Use `create_file` tool** for creating new files or complete rewrites
- ❌ **Avoid `sed`** - platform-specific syntax (macOS requires `sed -i ''`, Linux uses `sed -i`)
- ❌ **Avoid `awk`, `perl -i`** - harder to debug, platform differences

**Why**: The `edit_file` tool is cross-platform, provides clear diffs, and has built-in safety checks.

**Example - WRONG**:
```bash
sed -i.bak 's/oldtext/newtext/g' file.ts  # Creates .bak files, platform-specific
```

**Example - CORRECT**:
```
edit_file(path="file.ts", old_str="oldtext", new_str="newtext", replace_all=true)
```

### Handling Generated Files & Auto-formatting

**Problem**: Generated files (like `asset-sizes.md`) or automated formatting changes (like `prettier` runs) often cause merge conflicts because they change frequently and can affect many lines.

**Solution**: 
1. When merging or rebasing, **drop your changes** to the generated/formatted file (use `--ours` or `--theirs` depending on direction, or simply revert the file).
2. **Regenerate or reformat** at the very end of your process by running the build or format command (e.g., `npm run build` or `npm run lint:fix`).
3. **Commit the result** in a separate commit or amend your changes.

**Best Practice**: Isolate these changes in their own commits (e.g., "chore: Update asset-sizes.md" or "style: Run prettier"). This makes them easy to drop and recreate during rebases. The same applies to `npm install` updates (`package-lock.json`).

**Why**: Resolving conflicts in generated output or massive formatting changes is tedious and error-prone. It's safer and faster to re-run the tool that produced the output.

## Git Rebase & Interactive Editors

**Problem**: `git rebase` and other interactive commands often hang waiting for an editor to close when run via `Bash` tool.

**Solution**: Always set `GIT_EDITOR=true` (or another non-interactive command) when running rebase operations.

**Example**:
```bash
GIT_EDITOR=true git rebase -i HEAD~3
# or
GIT_EDITOR=true git rebase --continue
```

## Issue Tracking with bd (beads)

Track ALL work in beads—no markdown TODOs, no TodoWrite tool.

> **Update note**: This section mirrors `bd prime` output. Update after upgrading bd.

### Session Close Protocol

**Before saying "done" or "complete", run this checklist:**

```
[ ] 1. git status              (check what changed)
[ ] 2. git add <files>         (stage code changes)
[ ] 3. bd sync                 (commit beads changes)
[ ] 4. git commit -m "..."     (commit code)
[ ] 5. bd sync                 (commit any new beads changes)
[ ] 6. git push                (push to remote)
```

### Essential Commands

**Finding Work:**
- `bd ready` - Show issues ready to work (no blockers)
- `bd list --status=open` - All open issues
- `bd list --status=in_progress` - Your active work
- `bd show <id>` - Detailed issue view with dependencies

**Creating & Updating:**
- `bd create --title="..." --type=task|bug|feature` - New issue
- `bd update <id> --status=in_progress` - Claim work
- `bd close <id>` - Mark complete
- `bd close <id1> <id2> ...` - Close multiple issues at once

**Dependencies:**
- `bd dep add <issue> <depends-on>` - Add dependency
- `bd blocked` - Show all blocked issues

**Sync:**
- `bd sync` - Sync with git remote (run at session end)

### Common Workflows

**Starting work:**
```bash
bd ready                                  # Find available work
bd show <id>                              # Review issue details
bd update <id> --status=in_progress       # Claim it
```

**Completing work:**
```bash
bd close <id1> <id2> ...    # Close all completed issues at once
bd sync                     # Push to remote
```

### Managing AI-Generated Planning Documents

Store AI planning docs (PLAN.md, DESIGN.md, etc.) in `history/` directory to keep repo root clean.

## Context Management

- 🚨 **Use `Task` for large files**: When analyzing large logs (>100 lines) or configuration files, ALWAYS use the `Task` tool (subagent). This prevents the raw content from polluting the main conversation history.
- 🚨 **Grep before Read**: Never `Read` a large file to find a specific line. Use `Grep` first to locate the relevant section.
- 🚨 **Limit Git output**: Always use `-n` or similar limits when running `git log`.

For more details, see README.md and QUICKSTART.md.

## External CLIs

Sometimes the Atlassian or GitLab MCP servers may be unavailable or unstable. In these cases, you can use the command-line tools `glab` and `acli` directly via the `Bash` tool.

Instructions for these tools are not loaded by default to save context. If you need to use them, read the following files:
- **GitLab CLI (`glab`)**: `~/.config/generative-ai/tools/gitlab-cli.md`
- **Atlassian CLI (`acli`)**: `~/.config/generative-ai/tools/atlassian-cli.md` (includes Markdown→ADF formatting approach)

---

## Meta-Work Triggers

Proactively suggest documentation when you observe:

1. **User shares insight or distinction** → zettel (e.g., "20251208-chores-vs-projects.md")
2. **User corrects you (especially twice)** → update AGENTS.md with the gotcha
3. **Created reusable script/workflow** → document usage in relevant AGENTS.md
4. **Design decision made** → capture rationale where it belongs
5. **Hard-to-find info discovered** → make it easier to find next time
6. **Non-obvious fix applied** → document the technique

**Be specific**: "Create zettel: '20251208-topic.md'" not "should we document this?"
**Suggest immediately** when you notice the pattern—don't wait for end of discussion.

---

## Long-Running Script Guidelines

When writing scripts that may run for extended periods:

### Output & Logging
- **Verbose logs to files**, concise output to stdout/stderr
- **Print heartbeat every ~60 seconds** to avoid 5-minute Amp tool timeout
- Use a log file in `logs/` directory (gitignored)

### Resumability
- **Save progress incrementally** (every N items, or after each batch)
- Store state in a checkpoint file or database
- Scripts should be idempotent: running again skips completed work

### Error Handling
- Log errors but continue processing when possible
- Aggregate error summary at the end

### Integration
- Create orchestrator scripts that tie multiple steps together
- Integrate with existing orchestration (e.g., `sync_library.py`) when appropriate
- Scripts should work standalone but also composable

### LLM Cost Awareness
- Estimate costs before running batch LLM operations
- Use cheap models for filtering, expensive models for extraction
- Log token/cost estimates at start
- For smart model needs outside budget: `amp --visibility workspace -x 'prompt'` (uses Opus 4.5)
