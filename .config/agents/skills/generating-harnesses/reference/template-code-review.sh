#!/bin/bash
# ============================================================================
# CODE REVIEW ITERATION HARNESS — type-specific sections
#
# Pattern: Run review skills on a branch diff, address ALL findings
# aggressively, validate (build/lint/test), loop until the agent finds
# nothing worth fixing.
#
# Key insight: Agents under-fix. The prompt must push for significantly
# more aggressive fixes than the agent naturally suggests.
#
# Acceptance: always accept if validation passes (correctness checks exit 0).
# Stop condition: agent made NO changes (no diff between HEAD_BEFORE and
# HEAD_AFTER). This means the agent reviewed the diff and decided nothing
# was worth implementing.
#
# Unlike error-reduction or performance harnesses, there's no numeric metric
# to hill-climb. The iteration continues as long as the agent keeps finding
# and fixing things. "Stagnant" here means the agent chose not to commit,
# which is the stop signal.
#
# Configuration:
#   BASE_REF="main"            # what to diff against
#   CORRECTNESS_CMDS=("pnpm build" "pnpm lint" "pnpm test")
#   CORRECTNESS_LOGS=("/tmp/ralph-build.txt" "/tmp/ralph-lint.txt" "/tmp/ralph-test.txt")
# ============================================================================

# --- Type-specific validation ---

run_validation() {
    echo "=== Harness: running correctness checks... ===" | tee -a "$LOG_FILE"
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

acceptance_check() {
    # For code review: accept if all correctness checks pass.
    # The harness does NOT reject based on "not enough fixes" —
    # that's the prompt's job. If the agent committed and it passes
    # validation, accept it.
    local i=0
    for cmd in "${CORRECTNESS_CMDS[@]}"; do
        local ec
        ec=$(cat "/tmp/ralph-{{NAME}}-correct-${i}-ec.txt")
        if [ "$ec" -ne 0 ]; then
            REASON="${cmd} failed (exit $ec)"
            return 1
        fi
        i=$((i + 1))
    done
    return 0
}

snapshot_counts() {
    local commit_count
    commit_count=$(git rev-list --count "${BASE_REF}..HEAD" 2>/dev/null || echo "?")
    echo "commits=$commit_count"
}

check_done() {
    # Code review is "done" when the agent stops making changes.
    # This is detected by the main loop: HEAD_AFTER == HEAD_BEFORE → stagnant.
    # After MAX_STAGNANT (typically 1 for code review), we stop.
    # So check_done always returns false — we rely on stagnant detection.
    return 1
}

# BASELINE_SETUP:
#   # Verify all correctness checks pass at baseline
#   for i in $(seq 0 $((${#CORRECTNESS_CMDS[@]} - 1))); do
#       ec=$(cat "/tmp/ralph-{{NAME}}-correct-${i}-ec.txt")
#       if [ "$ec" -ne 0 ]; then
#           echo "FATAL: correctness check $i failed at baseline" | tee -a "$LOG_FILE"
#           echo "Fix these before running the review harness." | tee -a "$LOG_FILE"
#           rm -f "$SENTINEL"; exit 1
#       fi
#   done
#   echo "=== Baseline: all checks passing ===" | tee -a "$LOG_FILE"

# ============================================================================
# GOAL prompt for code review iteration
# ============================================================================
#
# The GOAL for code review is fundamentally different from error/perf:
#
# GOAL='Review and fix code quality issues. Working directory: '"$WORK_DIR"'. Branch: '"$BRANCH"'.
#
# ## What to review
#
# Run BOTH review skills on the branch diff:
#   1. Use the `review` skill (custom — confidence-based, catches code hygiene)
#   2. Use the `code-review` skill (builtin — catches design issues, security)
#
# The diff to review: `git diff '"$BASE_REF"'...HEAD`
#
# ## Aggressiveness policy (IMMUTABLE)
#
# Address ALL findings from both review skills. Agents naturally under-fix —
# you must push yourself to address significantly more findings than feels
# comfortable. The harness validates correctness automatically, so be bold:
#
# - Fix every finding that is clearly correct (confidence ≥ 7/10)
# - Fix findings that are probably correct (confidence 5-6/10) unless the
#   risk of regression is high
# - For low-confidence findings (< 5/10): fix if trivial, skip if risky
# - When in doubt, fix it — the harness will catch regressions
#
# ## What NOT to do
#
# - Do NOT just add comments explaining issues — fix the code
# - Do NOT skip findings because "it works fine as-is"
# - Do NOT make only the safe/easy fixes — address the hard ones too
# - Do NOT reorganize or refactor code beyond what the findings require
#
# ## Steps
#
# 1. Read '"$STATE_FILE"' for what was fixed in previous iterations
# 2. Generate the diff: `git diff '"$BASE_REF"'...HEAD`
# 3. Run both review skills on the diff
# 4. Collect ALL findings from both skills
# 5. Address every finding (see aggressiveness policy above)
# 6. Validate: run build, lint, and tests
# 7. Commit: git add -u && git commit -m "review: address review findings"
# 8. Update '"$STATE_FILE"' with what you fixed
#
# If you reviewed the diff and found nothing worth implementing, make NO
# commit and exit cleanly. The harness will detect this as the stop signal.
#
# ## End-of-iteration contract (IMMUTABLE)
#
# Either:
# 1. Exactly one new commit with fixes and a clean working tree, OR
# 2. No commit (you reviewed and found nothing actionable) — this stops the loop
#
# Never leave uncommitted changes. Never push.'

# ============================================================================
# Notes on MAX_STAGNANT for code review
# ============================================================================
#
# For code review, set MAX_STAGNANT=1. The stop condition IS the agent
# choosing not to commit. Unlike error-reduction where stagnation means
# the agent is stuck, in code review it means the agent is done.
#
# Also consider MAX_ITERATIONS=10 — code review shouldn't need 50 iterations.
