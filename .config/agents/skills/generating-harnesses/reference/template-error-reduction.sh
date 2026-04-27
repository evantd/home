#!/bin/bash
# ============================================================================
# ERROR REDUCTION HARNESS — type-specific sections
#
# Pattern: Drive an error count (build errors, lint errors, test failures)
# toward zero. Accept if total errors decrease, reject if same or worse.
#
# Acceptance criteria:
#   - Primary metric must not increase (e.g., codemod errors)
#   - Secondary metric may increase ONLY if primary improved
#   - At least one metric must improve
#
# Example validation commands (customize per project):
#   BUILD_CMD="pnpm build > /tmp/ralph-build.txt 2>&1"
#   LINT_CMD="pnpm lint:ts > /tmp/ralph-lint.txt 2>&1"
#   ERROR_PATTERN="error TS"   # grep pattern to count errors
#   ERROR_FILE="/tmp/ralph-lint.txt"
# ============================================================================

# --- Helpers ---

# Count occurrences of a pattern in a file. Returns $missing if file doesn't exist.
count_matches() {
    local pattern=$1 file=$2 missing=${3:-999}
    if [ ! -f "$file" ]; then
        echo "$missing"
        return 0
    fi
    grep -c -- "$pattern" "$file" 2>/dev/null || true
}

# --- Type-specific validation ---
#
# These functions replace the {{placeholders}} in template-common.sh.
# Customize the commands, patterns, and file paths for your project.

# VALIDATION_COMMANDS:
run_validation() {
    echo "=== Harness: running build + lint... ===" | tee -a "$LOG_FILE"
    cd "$WORK_DIR"
    # Replace with your build command:
    $BUILD_CMD || true
    # Replace with your lint command:
    $LINT_CMD || true
}

# Baseline tracking variables (set after initial validation)
PREV_PRIMARY=999
PREV_SECONDARY=999

# BASELINE_SETUP:
# After initial run_validation, capture baseline counts:
#   PREV_PRIMARY=$(count_matches "$PRIMARY_PATTERN" "$PRIMARY_FILE")
#   PREV_SECONDARY=$(count_matches "$SECONDARY_PATTERN" "$SECONDARY_FILE")
#   echo "=== Baseline: primary=$PREV_PRIMARY secondary=$PREV_SECONDARY ===" | tee -a "$LOG_FILE"

# ACCEPTANCE_LOGIC:
acceptance_check() {
    local cur_primary cur_secondary
    cur_primary=$(count_matches "$PRIMARY_PATTERN" "$PRIMARY_FILE")
    cur_secondary=$(count_matches "$SECONDARY_PATTERN" "$SECONDARY_FILE")

    if [ "$cur_primary" -gt "$PREV_PRIMARY" ]; then
        REASON="primary errors increased ($PREV_PRIMARY → $cur_primary)"
        return 1
    elif [ "$cur_primary" -eq "$PREV_PRIMARY" ] && [ "$cur_secondary" -gt "$PREV_SECONDARY" ]; then
        REASON="secondary errors increased ($PREV_SECONDARY → $cur_secondary) without primary improvement"
        return 1
    elif [ "$cur_primary" -eq "$PREV_PRIMARY" ] && [ "$cur_secondary" -eq "$PREV_SECONDARY" ]; then
        REASON="no change (primary=$cur_primary secondary=$cur_secondary)"
        return 1
    fi

    # Accepted — update baselines in UPDATE_PREV_ON_ACCEPT
    return 0
}

# UPDATE_PREV_ON_ACCEPT:
#   PREV_PRIMARY=$(count_matches "$PRIMARY_PATTERN" "$PRIMARY_FILE")
#   PREV_SECONDARY=$(count_matches "$SECONDARY_PATTERN" "$SECONDARY_FILE")

# SNAPSHOT_COUNTS:
snapshot_counts() {
    local p s
    p=$(count_matches "$PRIMARY_PATTERN" "$PRIMARY_FILE")
    s=$(count_matches "$SECONDARY_PATTERN" "$SECONDARY_FILE")
    echo "primary=$p secondary=$s"
}

# CHECK_DONE:
check_done() {
    local p s
    p=$(count_matches "$PRIMARY_PATTERN" "$PRIMARY_FILE")
    s=$(count_matches "$SECONDARY_PATTERN" "$SECONDARY_FILE")
    [ "$p" -eq 0 ] && [ "$s" -eq 0 ]
}

# ============================================================================
# GOAL prompt structure for error reduction
# ============================================================================
#
# The GOAL should include:
#
# 1. What the code does / what you're fixing
# 2. Correctness contract (what's never allowed — e.g., no `as any`)
# 3. Error types and how they relate
# 4. Acceptance rules (matches acceptance_check logic above)
# 5. Steps: read state → analyze errors → implement fix → validate → commit
# 6. Boldness policy + one-commit contract
#
# Example GOAL snippet for error reduction:
#
#   Fix build and lint errors. Working directory: $WORK_DIR. Branch: $BRANCH.
#
#   ## Acceptance rules (IMMUTABLE)
#   - Primary errors must never increase
#   - Secondary errors may increase ONLY if primary decreased
#   - At least one must improve — no stagnation
#
#   ## Steps
#   1. Read $STATE_FILE for what's been tried and current counts
#   2. Read build output: grep for error patterns in /tmp/ralph-build.txt
#   3. Read lint output: grep for error patterns in /tmp/ralph-lint.txt
#   4. Pick the top error pattern, analyze root cause, implement fix
#   5. Commit: git add <files> && git commit -m "prefix: <describe>"
