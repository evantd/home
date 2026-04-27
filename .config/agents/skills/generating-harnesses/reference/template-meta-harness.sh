#!/bin/bash
# Ralph Wiggum META-HARNESS — outer wrapper for the two-layer pattern.
# Runs the inner harness for a short batch, then invokes amp itself to
# reassess: tune the inner script, seed a design change in the codebase,
# or no-op. Cycle until done or stopped.
#
# Cross-script contract with inner:
#   - Inner reads RALPH_MAX_ITERATIONS env var for batch size
#   - Inner writes /tmp/ralph-{{NAME}}-exit-reason.txt on every exit path
#   - Inner sentinel: <repo>/.ralph-{{NAME}}-continue (recreated each cycle)
#   - Meta sentinel:  <repo>/.ralph-{{NAME}}-meta-continue
#   - Shared state file: /tmp/ralph-{{NAME}}-state.md (meta appends `## Meta cycle N`)
#
# Stop:  rm {{WORK_DIR}}/.ralph-{{NAME}}-meta-continue
# Watch: tail -f /tmp/ralph-{{NAME}}-meta.log

set -uo pipefail

# ============================================================================
# Configuration — fill these in
# ============================================================================

WORK_DIR="{{WORK_DIR}}"
BRANCH="{{BRANCH}}"

INNER_SCRIPT="/tmp/run-ralph-{{NAME}}.sh"
INNER_SENTINEL="$WORK_DIR/.ralph-{{NAME}}-continue"
META_SENTINEL="$WORK_DIR/.ralph-{{NAME}}-meta-continue"

# Inner runs for this many iterations per cycle, then meta reassesses.
# Short batches (10-20) catch stuck patterns early; longer batches reduce
# meta-call frequency.
INNER_ITERATIONS_PER_CYCLE="${META_INNER_ITERATIONS:-15}"
MAX_META_CYCLES="${META_MAX_CYCLES:-10}"

# Inner contract files
EXIT_REASON_FILE="/tmp/ralph-{{NAME}}-exit-reason.txt"
PROGRESS_FILE="/tmp/ralph-{{NAME}}-progress.txt"
STATE_FILE="/tmp/ralph-{{NAME}}-state.md"

# Meta-specific files
META_LOG="/tmp/ralph-{{NAME}}-meta.log"
META_PROMPT_FILE="/tmp/ralph-{{NAME}}-meta-prompt.txt"

# Hard correctness gate (also enforced by inner; meta double-checks after
# any design-seed amp call). Optional — leave empty if no checksum applies.
BASELINE_CHECKSUM="{{BASELINE_CHECKSUM:-}}"
# Command that produces the current checksum to compare against BASELINE_CHECKSUM.
# Leave empty to skip the post-seed checksum verification.
CHECKSUM_COMMAND="{{CHECKSUM_COMMAND:-}}"

# Lock to prevent concurrent meta runs
LOCK_DIR="/tmp/ralph-{{NAME}}-meta.lock"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    echo "Another meta loop is already running (lock: $LOCK_DIR). Remove if stale."
    exit 1
fi
trap 'rm -rf "$LOCK_DIR"' EXIT

# ============================================================================
# Helpers
# ============================================================================

log() {
    echo "[meta $(date +%H:%M:%S)] $*" | tee -a "$META_LOG"
}

git_head() {
    git -C "$WORK_DIR" rev-parse HEAD
}

current_checksum() {
    [ -z "$CHECKSUM_COMMAND" ] && echo "" && return 0
    eval "$CHECKSUM_COMMAND"
}

build_meta_prompt() {
    local exit_reason recent_state recent_progress
    exit_reason=$(cat "$EXIT_REASON_FILE" 2>/dev/null || echo "(no exit reason file)")
    recent_state=$(tail -200 "$STATE_FILE" 2>/dev/null || echo "(no state file)")
    recent_progress=$(tail -30 "$PROGRESS_FILE" 2>/dev/null || echo "(no progress file)")

    cat <<META_PROMPT
# Meta Reassessment — {{NAME}}

You are the META layer above a hill-climbing harness on branch \`$BRANCH\`.
The inner harness (\`$INNER_SCRIPT\`) just finished a batch.
Your job: read the state, diagnose, and apply ONE focused intervention.

## Inner harness exit reason

\`\`\`
$exit_reason
\`\`\`

## Recent state file (last 200 lines)

\`\`\`
$recent_state
\`\`\`

## Recent progress (last 30 iterations)

\`\`\`
$recent_progress
\`\`\`

## Decision tree — pick EXACTLY ONE

### (A) Harness tuning
Edit \`$INNER_SCRIPT\` only. Targets:
- Adjust gate thresholds with rationale
- Tighten or loosen the per-iteration prompt
- Improve error capture / state-file feedback
- Add new transient-error patterns to the API-error scan

After editing, validate: \`bash -n $INNER_SCRIPT\`. DO NOT edit the codebase.

### (B) Design seed
Edit code in \`$WORK_DIR\` to unblock a structural blocker the inner agent
can't break through alone (new abstraction, predicate relocation,
type-system change, etc.).

After editing, you MUST:
1. Run the project's build/lint/test commands and confirm they pass
2. Verify any correctness checksum (e.g. byte-identical generated output)
3. Commit on \`$BRANCH\` with a message starting \`[META design seed]\`
4. Push the branch
5. Document the seed in the project's refactor roadmap / state file

DO NOT edit the harness in this mode.

### (C) No-op
If the inner is making good progress, append a brief
\`## Meta cycle N — no-op (rationale)\` entry to the state file.

## Hard constraints

- Pure changes only; no shortcuts that bypass the hill-climb's safety gates.
- ONE intervention per meta cycle. Mode (A) OR (B) OR (C) — not multiple.
- Project-specific constraints listed below take priority.

{{PROJECT_CONSTRAINTS}}

## What to record

Append at the END of \`$STATE_FILE\`:

\`\`\`
## Meta cycle N — <mode A/B/C>: <one-line summary>

**Diagnosis**: <why this intervention>
**Action**: <what you did, with file paths>
**Validation**: <build/lint/checksum results, or "n/a (mode A)">
**Expected next-cycle effect**: <what the inner should do better>
\`\`\`

Replace N with the next sequential meta cycle number (look at existing
\`## Meta cycle\` headers).
META_PROMPT
}

# ============================================================================
# Setup
# ============================================================================

mkdir -p "$(dirname "$META_LOG")"
echo "" >> "$META_LOG"
log "===================================================================="
log "Meta-harness {{NAME}} started. Branch: $BRANCH"
log "Inner batch size: $INNER_ITERATIONS_PER_CYCLE iterations/cycle"
log "Max meta cycles: $MAX_META_CYCLES"
log "Stop: rm $META_SENTINEL"
log "===================================================================="

touch "$META_SENTINEL"

CURRENT_BRANCH=$(git -C "$WORK_DIR" branch --show-current)
if [ "$CURRENT_BRANCH" != "$BRANCH" ]; then
    log "ERROR: not on $BRANCH (currently on $CURRENT_BRANCH). Aborting."
    exit 1
fi

# ============================================================================
# Main loop
# ============================================================================

CYCLE=0
while [ "$CYCLE" -lt "$MAX_META_CYCLES" ]; do
    CYCLE=$((CYCLE + 1))

    if [ ! -f "$META_SENTINEL" ]; then
        log "Meta sentinel removed. Stopping."
        break
    fi

    log "===== Cycle $CYCLE/$MAX_META_CYCLES — running inner ($INNER_ITERATIONS_PER_CYCLE iters) ====="

    touch "$INNER_SENTINEL"
    : > "$EXIT_REASON_FILE"

    INNER_EC=0
    RALPH_MAX_ITERATIONS="$INNER_ITERATIONS_PER_CYCLE" bash "$INNER_SCRIPT" || INNER_EC=$?

    EXIT_REASON=$(cat "$EXIT_REASON_FILE" 2>/dev/null || echo "(unknown — no exit reason file)")
    log "Inner finished. exit=$INNER_EC reason=$EXIT_REASON"

    # Don't waste meta cycles on amp infrastructure problems.
    if echo "$EXIT_REASON" | grep -q '^amp_outage:'; then
        log "Inner halted due to amp outage. Sleeping 5min before retry; not invoking meta amp."
        sleep 300
        continue
    fi

    # User-driven stop propagates up.
    if echo "$EXIT_REASON" | grep -q '^sentinel_removed:'; then
        log "Inner stopped via sentinel — assuming user wants meta to stop too."
        break
    fi

    log "===== Cycle $CYCLE — meta reassessment ====="

    HEAD_BEFORE=$(git_head)
    CHECKSUM_BEFORE=$(current_checksum)

    build_meta_prompt > "$META_PROMPT_FILE"
    log "Meta prompt: $META_PROMPT_FILE ($(wc -l < "$META_PROMPT_FILE") lines)"

    META_AMP_EC=0
    amp < "$META_PROMPT_FILE" 2>&1 | tee -a "$META_LOG" || META_AMP_EC=$?
    log "Meta amp exit: $META_AMP_EC"

    HEAD_AFTER=$(git_head)
    CHECKSUM_AFTER=$(current_checksum)

    if [ "$HEAD_AFTER" != "$HEAD_BEFORE" ]; then
        # Mode B: design seed. Verify any correctness checksum.
        if [ -n "$BASELINE_CHECKSUM" ] && [ "$CHECKSUM_AFTER" != "$BASELINE_CHECKSUM" ]; then
            log "ERROR: meta design seed broke checksum baseline ($CHECKSUM_AFTER ≠ $BASELINE_CHECKSUM). Reverting."
            git -C "$WORK_DIR" reset --hard "$HEAD_BEFORE" 2>&1 | tee -a "$META_LOG"
            {
                echo ""
                echo "## Meta cycle $CYCLE — REVERTED (checksum drift)"
                echo "**Action**: meta amp committed but broke checksum baseline; reverted to $HEAD_BEFORE"
            } >> "$STATE_FILE"
        else
            log "Meta design seed accepted (HEAD $HEAD_BEFORE → $HEAD_AFTER)"
        fi
    else
        # Mode A or C: harness edit or no-op. Verify inner still parses.
        if ! bash -n "$INNER_SCRIPT" 2>/dev/null; then
            log "ERROR: meta amp broke inner harness syntax. Manual intervention needed."
            break
        fi
    fi

    log "===== Cycle $CYCLE complete ====="
    sleep 5
done

log "Meta-harness {{NAME}} stopped after $CYCLE cycles."
rm -f "$META_SENTINEL"
