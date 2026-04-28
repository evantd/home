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
    local interrupt_mode="${1:-no}"
    local batch_iters="${2:-?}"
    local batch_duration="${3:-?}"
    local exit_reason recent_state recent_progress meta_history
    exit_reason=$(cat "$EXIT_REASON_FILE" 2>/dev/null || echo "(no exit reason file)")
    # Always show a wide window — meta reassessment should consider the
    # strategic arc across many cycles, not just this batch. The
    # "no-op because nothing happened this cycle" failure mode comes
    # from too-narrow a view.
    recent_state=$(tail -1500 "$STATE_FILE" 2>/dev/null || echo "(no state file)")
    # Compressed strategic history: every prior meta-cycle header.
    meta_history=$(grep -E '^## Meta cycle ' "$STATE_FILE" 2>/dev/null || echo "(no meta cycles yet)")
    recent_progress=$(tail -200 "$PROGRESS_FILE" 2>/dev/null || echo "(no progress file)")

    cat <<META_PROMPT
# Meta Reassessment — {{NAME}}

You are the META layer above a hill-climbing harness on branch \`$BRANCH\`.
The inner harness (\`$INNER_SCRIPT\`) just finished a batch.
Your job: read the state, diagnose, and apply ONE focused intervention.

$(if [ "$interrupt_mode" = "yes" ]; then cat <<'INTERRUPT'

## ⚠️  This is a USER-REQUESTED CYCLE INTERRUPT — read carefully

The user removed the inner sentinel mid-batch (or before the inner had
made meaningful progress) while leaving the meta sentinel intact. **This
is a deliberate signal that the inner appears unproductive and the meta
should look BROADER than just this cycle.**

**Critical implications for your diagnosis:**

1. **Do NOT default to Mode (C) no-op just because this batch shows
   little/no signal.** That is the failure mode the user is reacting to.
   The user already knows this batch has thin signal — that's why they
   interrupted it. They want you to engage with the LONGER arc.

2. **Treat the full meta history and progress trajectory as primary
   evidence**, not just the most recent few iterations. Look at the
   pattern across ALL prior meta cycles (see \`meta_history\` below) and
   the full progress window. Ask: across the strategic arc, is the
   inner converging on its hard target? If progress stalled cycles ago
   and never resumed, the user is right to interrupt — your job is to
   figure out what structural intervention would unstick it.

3. **Strongly prefer Mode (B) design seed or Mode (A) prompt tuning.**
   If structural progress has been flat across several recent cycles,
   that's a structural blocker → Mode (B). If the inner has been chasing
   the wrong target (e.g. line-golf in doomed code), retighten the
   prompt → Mode (A).

4. **Mode (C) no-op is allowed only if** the long-term arc clearly shows
   real structural progress that would resume on the next batch with no
   changes. Spell out that evidence explicitly if you choose Mode (C);
   otherwise default to A or B.
INTERRUPT
fi)

## This batch's productivity

- **Iterations completed**: $batch_iters (inner cap was \`$INNER_ITERATIONS_PER_CYCLE\`)
- **Wall-clock duration**: ${batch_duration}s
- **Exit reason**: \`$exit_reason\`

A short batch (low iterations, short duration) is itself suspicious — it
means the inner barely had a chance to climb. Don't read "few iterations"
as "no signal"; read it as "not enough work happened, what's blocking it?"

## Inner harness exit reason (raw)

\`\`\`
$exit_reason
\`\`\`

## All prior meta cycles (compressed strategic history)

\`\`\`
$meta_history
\`\`\`

## Recent state file

\`\`\`
$recent_state
\`\`\`

## Recent progress (last 200 iterations)

\`\`\`
$recent_progress
\`\`\`

## Cross-cycle trajectory (REQUIRED reading before deciding)

**Before deciding on any mode, build an explicit picture of the
structural-progress metric (whatever your project defines as the hard
target — error count, case count, perf threshold, etc.) across cycles.**
Do this:

1. Scan the meta_history above and the progress file for the metric's
   value at the END of each prior cycle. Sketch the series in your
   diagnosis: e.g. "cycle 5 ended at metric=12, cycle 6 at 7, cycle 7
   at 7, cycle 8 at 7".
2. **If the structural metric has been flat across 2+ recent cycles,
   that IS the signal — regardless of what happened this batch.** A
   short or zero-iter batch on top of a multi-cycle plateau is
   overdetermined for intervention, not evidence of "nothing to act on".
3. Only consider Mode (C) no-op if the cross-cycle trajectory is
   actively dropping. Spell out the numbers in your diagnosis.

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

    # Capture batch-start metadata so we can quantify productivity.
    BATCH_START_TS=$(date +%s)
    PROGRESS_LINES_BEFORE=$(wc -l < "$PROGRESS_FILE" 2>/dev/null || echo 0)
    PROGRESS_LINES_BEFORE=${PROGRESS_LINES_BEFORE// /}

    INNER_EC=0
    RALPH_MAX_ITERATIONS="$INNER_ITERATIONS_PER_CYCLE" bash "$INNER_SCRIPT" || INNER_EC=$?

    BATCH_END_TS=$(date +%s)
    BATCH_DURATION=$((BATCH_END_TS - BATCH_START_TS))
    PROGRESS_LINES_AFTER=$(wc -l < "$PROGRESS_FILE" 2>/dev/null || echo 0)
    PROGRESS_LINES_AFTER=${PROGRESS_LINES_AFTER// /}
    BATCH_ITERS=$((PROGRESS_LINES_AFTER - PROGRESS_LINES_BEFORE))

    EXIT_REASON=$(cat "$EXIT_REASON_FILE" 2>/dev/null || echo "(unknown — no exit reason file)")
    log "Inner finished. exit=$INNER_EC reason=$EXIT_REASON iters=$BATCH_ITERS duration=${BATCH_DURATION}s"

    # Don't waste meta cycles on amp infrastructure problems.
    if echo "$EXIT_REASON" | grep -q '^amp_outage:'; then
        log "Inner halted due to amp outage. Sleeping 5min before retry; not invoking meta amp."
        sleep 300
        continue
    fi

    # Detect interrupt-or-suspicious-short-batch.
    #  - If META sentinel ALSO gone → user wants the whole thing stopped.
    #  - If exit reason says sentinel_removed → user-requested cycle interrupt.
    #  - If batch is suspiciously short (<= 2 iters AND < 5 min) → treat
    #    as effectively interrupted regardless of exit reason. The signal
    #    is "inner barely produced anything", which is itself a reason
    #    for the meta to look broader.
    INTERRUPT_MODE="no"
    if echo "$EXIT_REASON" | grep -q '^sentinel_removed:'; then
        if [ ! -f "$META_SENTINEL" ]; then
            log "Inner stopped via sentinel AND meta sentinel also gone — full stop."
            break
        fi
        log "Inner sentinel removed but meta sentinel intact — treating as user-requested cycle interrupt; running meta reassessment with broader-history framing."
        INTERRUPT_MODE="yes"
    elif [ "$BATCH_ITERS" -le 2 ] && [ "$BATCH_DURATION" -lt 300 ]; then
        log "Suspicious short batch (iters=$BATCH_ITERS, duration=${BATCH_DURATION}s) — treating as effectively interrupted; running meta reassessment with broader-history framing."
        INTERRUPT_MODE="yes"
    fi

    log "===== Cycle $CYCLE — meta reassessment (interrupt_mode=$INTERRUPT_MODE iters=$BATCH_ITERS duration=${BATCH_DURATION}s) ====="

    HEAD_BEFORE=$(git_head)
    CHECKSUM_BEFORE=$(current_checksum)

    build_meta_prompt "$INTERRUPT_MODE" "$BATCH_ITERS" "$BATCH_DURATION" > "$META_PROMPT_FILE"
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
