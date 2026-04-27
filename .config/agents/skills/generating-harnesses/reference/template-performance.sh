#!/bin/bash
# ============================================================================
# PERFORMANCE OPTIMIZATION HARNESS — type-specific sections
#
# Pattern: Optimize wall-clock time while maintaining correctness.
# Accept if faster (by >THRESHOLD%) AND all correctness checks pass.
#
# Key differences from error reduction:
#   - Timing run: measures wall-clock time with high-resolution timer
#   - Profiling run (optional): captures CPU profile for agent analysis
#   - Correctness is binary (exit codes), not a count
#   - Threshold: must improve by >N% to filter out noise
#   - Rejected attempts are categorized: SLOWER vs ERRORS-but-faster
#     (SLOWER = don't retry; ERRORS = fix bugs and retry)
#
# Example configuration:
#   TIMING_CMD="bash scripts/run-thing.sh"
#   TIMING_LOG="/tmp/ralph-perf-timing.txt"
#   CORRECTNESS_CMDS=("pnpm build" "pnpm lint:ts" "pnpm test")
#   CORRECTNESS_LOGS=("/tmp/ralph-build.txt" "/tmp/ralph-lint.txt" "/tmp/ralph-test.txt")
#   IMPROVEMENT_THRESHOLD=0.98  # must be < 98% of previous (i.e., 2% faster)
#   TARGET_SECONDS=30           # stop when under this
# ============================================================================

# --- Timing ---

WALLCLOCK_FILE="/tmp/ralph-{{NAME}}-wallclock.txt"

run_timing() {
    echo "=== Harness: TIMING RUN ===" | tee -a "$LOG_FILE"
    cd "$WORK_DIR"

    local start end elapsed ec
    start=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
    ec=0
    $TIMING_CMD > "$TIMING_LOG" 2>&1 || ec=$?
    end=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
    elapsed=$(perl -e "printf '%.1f', $end - $start")

    echo "$elapsed" > "$WALLCLOCK_FILE"
    echo "$ec" > /tmp/ralph-{{NAME}}-timing-ec.txt
    echo "  Wall-clock: ${elapsed}s (exit=$ec)" | tee -a "$LOG_FILE"
}

# --- Correctness checks (all must exit 0) ---

run_correctness() {
    echo "=== Harness: CORRECTNESS CHECKS ===" | tee -a "$LOG_FILE"
    cd "$WORK_DIR"

    local i=0
    for cmd in "${CORRECTNESS_CMDS[@]}"; do
        local ec=0
        $cmd > "${CORRECTNESS_LOGS[$i]}" 2>&1 || ec=$?
        echo "$ec" > "/tmp/ralph-{{NAME}}-correct-${i}-ec.txt"
        echo "  ${cmd}: exit $ec" | tee -a "$LOG_FILE"
        i=$((i + 1))
    done
}

# --- Profiling (optional) ---

# If the agent needs CPU profiles to guide optimization, add a profiling run:
# run_profiling() {
#     NODE_OPTIONS="--cpu-prof --cpu-prof-dir=$PROFILE_DIR" $TIMING_CMD > /dev/null 2>&1 || true
#     # Find largest .cpuprofile and copy to $PROFILE_LATEST
# }

# --- Type-specific validation ---

PREV_WALLCLOCK=999

run_validation() {
    run_timing
    run_correctness
}

# BASELINE_SETUP:
#   PREV_WALLCLOCK=$(cat "$WALLCLOCK_FILE")
#   # Verify all correctness checks passed at baseline
#   for i in $(seq 0 $((${#CORRECTNESS_CMDS[@]} - 1))); do
#       ec=$(cat "/tmp/ralph-{{NAME}}-correct-${i}-ec.txt")
#       if [ "$ec" -ne 0 ]; then
#           echo "FATAL: correctness check $i failed at baseline (exit $ec)" | tee -a "$LOG_FILE"
#           rm -f "$SENTINEL"; exit 1
#       fi
#   done
#   echo "=== Baseline: wall=${PREV_WALLCLOCK}s (all checks passing) ===" | tee -a "$LOG_FILE"

acceptance_check() {
    local cur_wallclock threshold faster
    cur_wallclock=$(cat "$WALLCLOCK_FILE")

    # Check correctness first — all must exit 0
    local i=0
    for cmd in "${CORRECTNESS_CMDS[@]}"; do
        local ec
        ec=$(cat "/tmp/ralph-{{NAME}}-correct-${i}-ec.txt")
        if [ "$ec" -ne 0 ]; then
            REASON="${cmd} failed (exit $ec)"
            # Categorize: was it at least faster?
            local was_faster
            was_faster=$(echo "$cur_wallclock < $PREV_WALLCLOCK" | bc -l 2>/dev/null || echo "0")
            if [ "$was_faster" = "1" ]; then
                REASON="$REASON [ERRORS but faster — fix bugs and retry]"
            fi
            return 1
        fi
        i=$((i + 1))
    done

    # Check performance improvement
    threshold=$(echo "scale=3; $PREV_WALLCLOCK * $IMPROVEMENT_THRESHOLD" | bc -l 2>/dev/null || echo "$PREV_WALLCLOCK")
    faster=$(echo "$cur_wallclock < $threshold" | bc -l 2>/dev/null || echo "0")
    if [ "$faster" != "1" ]; then
        REASON="not faster (${PREV_WALLCLOCK}s → ${cur_wallclock}s, need < ${threshold}s) [SLOWER — don't retry]"
        return 1
    fi

    return 0
}

# UPDATE_PREV_ON_ACCEPT:
#   PREV_WALLCLOCK=$(cat "$WALLCLOCK_FILE")
#   # Optionally run profiling for next iteration:
#   # run_profiling

snapshot_counts() {
    local w
    w=$(cat "$WALLCLOCK_FILE" 2>/dev/null || echo "?")
    echo "wall=${w}s"
}

check_done() {
    local w
    w=$(cat "$WALLCLOCK_FILE" 2>/dev/null || echo "999")
    local met
    met=$(echo "$w < $TARGET_SECONDS" | bc -l 2>/dev/null || echo "0")
    [ "$met" = "1" ]
}

# ============================================================================
# GOAL prompt additions for performance
# ============================================================================
#
# The GOAL should additionally include:
#
# 1. What's being timed and what the target is
# 2. Where profile data lives (if applicable)
# 3. Boldness policy — escalate to structural changes when incremental
#    approaches plateau. If last 2+ iterations were no-commit or rejected,
#    attempt a larger refactor.
# 4. Example structural strategies (but not exhaustive — allow novel ideas)
# 5. Rejection categorization: SLOWER vs ERRORS explain in state file
#
# Example additions:
#
#   ## Performance target (IMMUTABLE)
#   Total execution time must be < 30 seconds. Current: ~300s.
#
#   ## Boldness policy (IMMUTABLE)
#   Always commit and let the harness judge. If the last 2+ iterations were
#   no-commit or flat-result, escalate to a structural change.
#   Example structural changes (not exhaustive):
#   - Two-phase analyze/apply
#   - Worker sharding
#   - Something else entirely — novel approaches welcome
