#!/bin/bash
# Ralph Wiggum harness — COMMON SKELETON
# Fill in: NAME, WORK_DIR, BRANCH, GOAL, validation functions, acceptance logic.
#
# Sentinel file: .ralph-{{NAME}}-continue — delete to stop gracefully.
#
# Usage:
#   /tmp/run-ralph-{{NAME}}.sh
#
# Stop:
#   rm {{WORK_DIR}}/.ralph-{{NAME}}-continue

set -uo pipefail

# ============================================================================
# Configuration — fill these in
# ============================================================================

SENTINEL=".ralph-{{NAME}}-continue"
ITERATION=0
STAGNANT=0
AMP_FAILURES=0
# Env-overridable so a meta-harness can run short batches.
MAX_ITERATIONS="${RALPH_MAX_ITERATIONS:-{{MAX_ITERATIONS:-50}}}"
MAX_STAGNANT="${RALPH_MAX_STAGNANT:-{{MAX_STAGNANT:-3}}}"
# Consecutive amp transient failures (API 4xx/5xx, network errors) that
# stop the harness — separate from MAX_STAGNANT so an amp outage doesn't
# look like agent-progress stalling.
MAX_AMP_FAILURES="${RALPH_MAX_AMP_FAILURES:-5}"

WORK_DIR="{{WORK_DIR}}"
BRANCH="{{BRANCH}}"

LOG_FILE="/tmp/ralph-{{NAME}}.log"
PROGRESS_FILE="/tmp/ralph-{{NAME}}-progress.txt"
STATE_FILE="/tmp/ralph-{{NAME}}-state.md"
# Written on every exit path for an optional meta-harness to read.
EXIT_REASON_FILE="/tmp/ralph-{{NAME}}-exit-reason.txt"
write_exit_reason() {
    echo "$1" > "$EXIT_REASON_FILE"
}

# Lock to prevent concurrent runs
LOCK_DIR="/tmp/ralph-{{NAME}}.lock"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    echo "Another Ralph loop is already running (lock: $LOCK_DIR). Remove if stale."
    exit 1
fi
trap 'rm -rf "$LOCK_DIR"' EXIT

# ============================================================================
# IMMUTABLE GOAL — embedded in script to prevent drift.
# Only mutable execution state goes in STATE_FILE.
# ============================================================================

GOAL='{{GOAL_TEXT}}

## Steps

1. Read '"$STATE_FILE"' for execution state (what has been tried, current status)
2. {{STEP_2_CONTEXT_INSTRUCTIONS}}
3. Analyze the current state and decide what to do
4. Implement the change
5. Validate before committing (the harness will also validate, but catching
   errors early saves an iteration)
6. Commit (DO NOT PUSH):
   git add {{FILES_TO_STAGE}}
   git commit -m "{{COMMIT_PREFIX}}: <describe what you changed>"

## Boldness policy (IMMUTABLE)

**Always commit and let the harness judge.** A no-commit iteration costs the
same wall-clock time as a rejected commit but produces zero signal.

You MUST end with exactly one new commit on '"$BRANCH"' and a clean working
tree. Never leave uncommitted changes behind. Never push.

## Architecture: strategy thread + Task subagents

You are the MAIN THREAD. Delegate long-running commands (builds, lints, tests)
to Task subagents to avoid burning context on polling loops. Do deep analysis
and decision-making in the main thread.

---

{{INJECTED_CONTEXT_MARKER}}'

# ============================================================================
# Helpers
# ============================================================================

build_prompt() {
    echo "$GOAL"
    echo ""
    # Inject source files the agent needs in context
    {{INJECT_FILES_BLOCK}}
    echo ""
    echo "## Current state"
    echo ""
    cat "$STATE_FILE"
}

# --- Seed state file if needed ---

if [ ! -f "$STATE_FILE" ]; then
    cat > "$STATE_FILE" << 'SEED'
{{STATE_FILE_SEED}}
SEED
fi

# ============================================================================
# Validation functions — TYPE-SPECIFIC, replace these
# ============================================================================

# run_validation: runs all validation commands after an iteration.
# Sets global variables that acceptance_check reads.
run_validation() {
    echo "=== Harness: running validation... ===" | tee -a "$LOG_FILE"
    cd "$WORK_DIR"
    {{VALIDATION_COMMANDS}}
}

# acceptance_check: returns 0 if accepted, 1 if rejected.
# Sets REASON on rejection.
acceptance_check() {
    {{ACCEPTANCE_LOGIC}}
}

# snapshot_counts: one-line summary for progress file.
snapshot_counts() {
    {{SNAPSHOT_COUNTS}}
}

# check_done: returns 0 if the goal is fully achieved.
check_done() {
    {{CHECK_DONE}}
}

# ============================================================================
# Main loop
# ============================================================================

cd "$WORK_DIR"
touch "$SENTINEL"
: > "$LOG_FILE"
: > "$PROGRESS_FILE"

echo "=== Ralph {{NAME}} loop started at $(date) ===" | tee -a "$LOG_FILE"
echo "To stop: rm $WORK_DIR/$SENTINEL" | tee -a "$LOG_FILE"
echo "Monitor: tail -f $LOG_FILE" | tee -a "$LOG_FILE"
echo "Progress: cat $PROGRESS_FILE" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# --- Establish baseline ---
run_validation
{{BASELINE_SETUP}}
echo "iter 0 (baseline): $(snapshot_counts) at $(date)" >> "$PROGRESS_FILE"

while [ -f "$SENTINEL" ]; do
    if check_done; then
        echo "=== DONE: Goal achieved after $ITERATION iterations. ===" | tee -a "$LOG_FILE"
        rm -f "$SENTINEL"
        break
    fi

    ITERATION=$((ITERATION + 1))
    echo "=== Iteration $ITERATION ($(date)) ===" | tee -a "$LOG_FILE"

    HEAD_BEFORE=$(git rev-parse HEAD)

    # --- amp call with resume-on-error retry ---
    # amp can print 4xx/5xx API errors (e.g. intermittent thinking-config
    # issues) but exit 0. Scan the output for transient patterns AND retry
    # by resuming the same thread (`amp threads continue --last`) so the
    # agent keeps its context — same UX as the interactive retry prompt.
    AMP_EC=0
    AMP_RETRIES=0
    MAX_AMP_RETRIES=4
    AMP_PROMPT_FILE="/tmp/ralph-{{NAME}}-amp-prompt-$ITERATION.txt"
    build_prompt > "$AMP_PROMPT_FILE"
    TRANSIENT_RE='Error: (4[0-9][0-9]|5[0-9][0-9]) |invalid_request_error|rate_limit_error|api_error|overloaded_error|connection (refused|reset|timeout)|network error'
    while [ "$AMP_RETRIES" -lt "$MAX_AMP_RETRIES" ]; do
        AMP_EC=0
        AMP_OUT_FILE="/tmp/ralph-{{NAME}}-amp-output-$ITERATION-$AMP_RETRIES.txt"
        if [ "$AMP_RETRIES" -eq 0 ]; then
            amp < "$AMP_PROMPT_FILE" > "$AMP_OUT_FILE" 2>&1 || AMP_EC=$?
        else
            echo "Retry the previous request." | amp threads continue --last > "$AMP_OUT_FILE" 2>&1 || AMP_EC=$?
        fi
        cat "$AMP_OUT_FILE" | tee -a "$LOG_FILE"
        if [ "$AMP_EC" -eq 0 ] && ! grep -qE "$TRANSIENT_RE" "$AMP_OUT_FILE"; then
            break
        fi
        AMP_RETRIES=$((AMP_RETRIES + 1))
        BACKOFF=$((20 * AMP_RETRIES))
        if [ "$AMP_EC" -ne 0 ]; then
            echo "=== amp exit $AMP_EC (retry $AMP_RETRIES/$MAX_AMP_RETRIES via 'threads continue --last' in ${BACKOFF}s) ===" | tee -a "$LOG_FILE"
        else
            MATCHED=$(grep -oE "$TRANSIENT_RE" "$AMP_OUT_FILE" | head -1)
            echo "=== amp API error: '$MATCHED' (retry $AMP_RETRIES/$MAX_AMP_RETRIES via 'threads continue --last' in ${BACKOFF}s) ===" | tee -a "$LOG_FILE"
            AMP_EC=1  # force nonzero so downstream gate treats this as transient if all retries exhaust
        fi
        sleep "$BACKOFF"
    done

    HEAD_AFTER=$(git rev-parse HEAD)
    DIRTY=$(git diff --name-only HEAD 2>/dev/null || true)

    # Iteration-level safety net: if all retries exhausted AND no commit,
    # treat as amp transient failure (don't bump STAGNANT). Cap consecutive
    # amp failures so a real outage halts cleanly.
    if [ "$AMP_EC" -ne 0 ] && [ "$HEAD_AFTER" = "$HEAD_BEFORE" ]; then
        echo "=== amp transient failure — skipping iteration without stagnant bump ===" | tee -a "$LOG_FILE"
        echo "iter $ITERATION: SKIPPED (amp transient) at $(date)" >> "$PROGRESS_FILE"
        AMP_FAILURES=$((AMP_FAILURES + 1))
        if [ "$AMP_FAILURES" -ge "$MAX_AMP_FAILURES" ]; then
            echo "=== amp transient failures hit cap ($AMP_FAILURES/$MAX_AMP_FAILURES). Stopping. ===" | tee -a "$LOG_FILE"
            write_exit_reason "amp_outage: $AMP_FAILURES consecutive transient failures"
            rm -f "$SENTINEL"
            break
        fi
        sleep 60
        continue
    fi
    AMP_FAILURES=0

    # Clean up any uncommitted tracked changes
    if [ -n "$DIRTY" ]; then
        echo "=== WARNING: Dirty tracked files. Reverting. ===" | tee -a "$LOG_FILE"
        echo "$DIRTY" | tee -a "$LOG_FILE"
        git checkout -- . 2>/dev/null || true
    fi

    # --- Harness enforcement ---

    if [ "$HEAD_AFTER" != "$HEAD_BEFORE" ]; then
        # Agent committed — validate and accept/reject
        run_validation

        ACCEPT=false
        REASON=""
        acceptance_check && ACCEPT=true

        if [ "$ACCEPT" = true ]; then
            echo "=== ACCEPTED: $(snapshot_counts) ===" | tee -a "$LOG_FILE"
            {{PUSH_COMMAND}}
            {{UPDATE_PREV_ON_ACCEPT}}
            STAGNANT=0
        else
            echo "=== REJECTED: $REASON. Reverting. ===" | tee -a "$LOG_FILE"

            # Record rejected attempt in state file BEFORE reverting
            # (state file is in /tmp/ so it survives the revert)
            COMMIT_MSG=$(git log -1 --pretty=%s 2>/dev/null || echo "(no message)")
            COMMIT_DIFF_STAT=$(git diff --stat HEAD~1 2>/dev/null | tail -1 || echo "(unknown)")
            {
                echo ""
                echo "### REJECTED iter $ITERATION: $COMMIT_MSG"
                echo "- Reason: $REASON"
                echo "- Diff: $COMMIT_DIFF_STAT"
            } >> "$STATE_FILE"

            git reset --hard "$HEAD_BEFORE" 2>&1 | tee -a "$LOG_FILE"
            run_validation  # Re-validate after revert to restore baseline state
            STAGNANT=$((STAGNANT + 1))
        fi
    else
        # No commit — stagnant
        STAGNANT=$((STAGNANT + 1))
        echo "=== No commit (stagnant=$STAGNANT/$MAX_STAGNANT) ===" | tee -a "$LOG_FILE"
    fi

    echo "iter $ITERATION: $(snapshot_counts) at $(date)" >> "$PROGRESS_FILE"
    echo "=== Progress: $(snapshot_counts) ===" | tee -a "$LOG_FILE"

    if [ "$STAGNANT" -ge "$MAX_STAGNANT" ]; then
        echo "=== No progress for $MAX_STAGNANT iterations. Stopping. ===" | tee -a "$LOG_FILE"
        write_exit_reason "stagnant: $STAGNANT consecutive iterations without progress"
        rm -f "$SENTINEL"
        break
    fi

    if [ ! -f "$SENTINEL" ]; then
        echo "Sentinel removed. Stopping." | tee -a "$LOG_FILE"
        write_exit_reason "sentinel_removed: user/meta requested stop"
        break
    fi

    if [ $ITERATION -ge $MAX_ITERATIONS ]; then
        echo "Reached iteration limit ($MAX_ITERATIONS). Stopping." | tee -a "$LOG_FILE"
        write_exit_reason "batch_complete: reached iteration limit ($MAX_ITERATIONS) cleanly"
        rm -f "$SENTINEL"
        break
    fi

    echo "=== Iteration $ITERATION complete. Next in 5s... ===" | tee -a "$LOG_FILE"
    sleep 5
done

# Fallback exit-reason write: if the loop exited at the `while [ -f $SENTINEL ]`
# check (sentinel removed during sleep or before first iteration), no in-body
# write_exit_reason ran and the file is empty. Meta layer needs a real reason
# to distinguish cycle-interrupt from other paths.
if [ ! -s "$EXIT_REASON_FILE" ]; then
    if [ ! -f "$SENTINEL" ]; then
        write_exit_reason "sentinel_removed: detected at while-loop check (between iterations)"
    else
        write_exit_reason "unknown: loop exited without explicit reason"
    fi
fi

echo "=== Ralph stopped after $ITERATION iterations. ===" | tee -a "$LOG_FILE"
echo ""
echo "Progress history:"
cat "$PROGRESS_FILE"
