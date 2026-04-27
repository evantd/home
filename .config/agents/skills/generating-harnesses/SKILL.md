---
name: generating-harnesses
description: "Generates bash harness scripts for iterative agent loops (the Ralph Wiggum pattern). Sequential compounding with test gating — each iteration invokes amp CLI, validates, accepts/rejects. Supports error reduction, performance optimization, code review iteration, and novel harness types. Triggers on: generate harness, ralph wiggum, iterative agent loop, agent harness, iteration loop"
---

# Generating Harnesses

Generate self-contained bash scripts that run iterative agent loops. The pattern:
a bash harness invokes `amp` CLI repeatedly, each time with a crafted prompt +
injected state. After each iteration, the harness validates the result and
accepts (keep + push) or rejects (revert). This is the "Ralph Wiggum" pattern —
sequential compounding with test gating.

## Design Principles

1. **Sequential compounding**: Same high-level instruction repeated; workspace state changes between iterations
2. **Hill-climbing with test gating**: Accept patches that improve outcomes, reject the rest
3. **Minimal viable harness first**: Start simple, layer complexity only when needed
4. **Extend the harness, don't nest**: Use `amp` CLI directly, not another agent framework
5. **State-driven progress**: Prompt stays roughly constant; context (files/test results) drives progress
6. **Boldness policy**: Always commit and let the harness judge. No-commit iterations waste the same wall-clock time as a rejected commit but produce zero signal. The prompt MUST require exactly one commit per iteration — remove any "or no commit" escape hatch.
7. **Robustness to amp transients**: API errors (4xx/5xx, `invalid_request_error`, etc.) sometimes appear in amp output even when amp exits 0. The retry loop MUST scan output for these patterns AND retry by RESUMING the thread (`amp threads continue --last`) so context isn't lost. Separate a `MAX_AMP_FAILURES` counter from `MAX_STAGNANT` so an amp outage doesn't look like agent stagnation.

## Workflow

### Step 1: Gather Parameters

Ask the user for these inputs (required marked with *):

| Parameter | Description | Example |
|-----------|-------------|---------|
| **Working directory*** | Absolute path to the project | `/Users/me/project/react-native` |
| **Branch*** | Git branch to work on | `jira/RN-2488` |
| **Objective*** | What to fix/optimize/review | "Drive type errors to zero", "Optimize build speed" |
| **Harness type** | One of: `error-reduction`, `performance`, `code-review`, or `custom` | `error-reduction` |
| **Validation commands*** | Commands to run after each iteration, with expected behavior | `pnpm build` (exit 0), `pnpm lint` (count errors) |
| **Acceptance criteria*** | How to decide accept vs reject | "Error count must decrease", "Must be >2% faster" |
| **Stop conditions** | When to declare victory | "Zero errors", "< 30s wall-clock" |
| **Files to inject** | Source files to include in the prompt for agent context | `scripts/transform.ts` |
| **State file seed** | Initial content for the cross-iteration state file | Error counts, known patterns |
| **MAX_ITERATIONS** | Default: 50 | |
| **MAX_STAGNANT** | Consecutive no-progress iterations before stopping. Default: 3-5 | |
| **Project context** | Any domain-specific rules, constraints, or guardrails | "Never use `as any`" |
| **Push on accept?** | Whether to `git push` after accepting. Default: yes | |

### Step 2: Choose Harness Type

If the user hasn't specified a type, infer from their objective:

- **Error reduction**: Driving a count (errors, warnings, failures) toward zero. Metric: error count must decrease.
- **Performance**: Optimizing speed while maintaining correctness. Metric: wall-clock time must decrease >N%. Correctness: all validation commands exit 0.
- **Code review iteration**: Running review skills, addressing findings, validating. Metric: no meaningful changes = done. Each iteration runs both `review` and `code-review` skills on the branch diff.
- **Custom**: User defines their own acceptance logic. Use the common structure but let them specify the validation/acceptance functions.

### Step 3: Generate the Script

Read `reference/template-common.sh` for the shared harness skeleton.
Read the type-specific reference file for the acceptance logic and prompt structure:
- `reference/template-error-reduction.sh`
- `reference/template-performance.sh`
- `reference/template-code-review.sh`

Assemble the final script by:
1. Starting from the common skeleton
2. Filling in user-specific values (paths, commands, branch, etc.)
3. Inserting the type-specific validation/acceptance logic
4. Embedding the GOAL prompt with user's objective, guardrails, and context
5. Writing the `build_prompt()` function to inject source files and state

### Step 4: Review with User

Present the generated script and explain:
- How to start it: `bash /tmp/run-ralph-<name>.sh`
- How to stop it: `rm <sentinel-file>`
- How to monitor: `tail -f <log-file>` and `cat <progress-file>`
- What acceptance criteria will be enforced

## Prompt Construction Guidelines

The prompt piped to `amp` has three parts:

1. **Immutable goal** (embedded in script): Objective, constraints, guardrails, correctness contract, step-by-step workflow. This never changes between iterations.
2. **Injected source/context** (from files): Key source files `cat`'d into the prompt so the agent has them in context without needing to read them.
3. **Mutable state** (from state file): Cross-iteration memory — what's been tried, current counts, what to try next, what failed. Lives in `/tmp/` so it survives git reverts.

### Prompt Best Practices

- **Be explicit about the commit contract**: "You MUST end with exactly one new commit and a clean working tree. Never leave uncommitted changes. Never push."
- **Push for boldness**: "Always commit and let the harness judge. A no-commit iteration wastes time and produces zero signal."
- **Recommend Task subagents**: For long-running validation (builds, tests), tell the agent to delegate to Task subagents to avoid burning main-thread context on polling.
- **Include what FAILED**: The state file should track rejected attempts so the agent doesn't retry the same approach.
- **Scope the diff**: For code-review type, tell the agent exactly what diff to review (e.g., `git diff main...HEAD`).

### Code Review Prompt Specifics

For the code-review harness type, the prompt must:
- Run BOTH `review` and `code-review` skills (they find non-overlapping issues)
- Address ALL findings aggressively — agents naturally under-fix. The prompt should say: "Address significantly more findings than you think are worth implementing. The harness will validate correctness — be aggressive."
- Commit after addressing findings (boldness policy applies)
- Stop condition: the agent reviewed the diff, found no actionable findings, and made no changes

## Common Harness Structure

Every harness has these components (see `reference/template-common.sh`):

```
Sentinel file     → touch to start, rm to stop gracefully
Lock directory    → mkdir prevents concurrent runs
Iteration loop    → while [ -f SENTINEL ]; MAX_ITERATIONS; MAX_STAGNANT
Per-iteration     → build_prompt | amp → validate → accept/reject
State file        → /tmp/ (survives git reverts), snapshot not log
Progress file     → one line per iteration, machine-parseable
Log file          → full amp output for debugging
Git flow          → HEAD_BEFORE → amp runs → HEAD_AFTER
                    if committed: validate → accept (push) or reject (reset --hard)
                    if no commit: stagnant++
Dirty check       → after amp, revert any uncommitted tracked changes
```

## Two-Layer Meta-Harness Pattern

For long-running refactors, performance work, or any harness where the inner
agent risks accumulating local-optimum cruft, layer a **meta harness** above
the inner one. The meta layer runs the inner for a short batch, then invokes
amp itself to reassess.

### When to add a meta layer

- Inner harness is expected to run >30 iterations (drift becomes likely)
- The work has structural blockers an inner agent can't break through alone
  (e.g. needs a new abstraction, predicate relocation, type-system change)
- You'd otherwise be doing manual mid-run "look at the trajectory and fix
  the prompt/gates" cycles between batches

### Composition

- **Inner** (existing harness): factored to take `MAX_ITERATIONS` from env
  (`RALPH_MAX_ITERATIONS`). Writes a structured exit-reason file
  (`/tmp/ralph-<name>-exit-reason.txt`) on every exit path so the meta layer
  knows why it stopped: `batch_complete`, `stagnant`, `amp_outage`,
  `sentinel_removed`.
- **Meta** (new wrapper): runs inner with a short batch size (10-20 iters),
  reads the exit reason + last 200 state-file lines + last 30 progress lines,
  then calls amp with a meta prompt. Meta amp picks ONE intervention:
  - **(A) Harness tuning** — edits the inner script (prompt, gates, capture).
    Validated by `bash -n`.
  - **(B) Design seed** — edits the codebase to unblock structural problems.
    Must respect full validation gates (build/lint/correctness checksums) and
    commit + push.
  - **(C) No-op** — records rationale; lets the inner keep climbing.
- Meta skips its amp call on `amp_outage` (sleeps and retries inner) and
  stops if the user removes the inner sentinel.

### Cross-script contract

- Inner sentinel: `<repo>/.ralph-<name>-continue` (recreated by meta each cycle)
- Meta sentinel: `<repo>/.ralph-<name>-meta-continue`
- Exit reason file: `/tmp/ralph-<name>-exit-reason.txt` (overwritten, not appended)
- State file: `/tmp/ralph-<name>-state.md` (shared — meta appends `## Meta cycle N` sections)
- Lock dirs: separate per layer

### When NOT to use a meta layer

- Single-objective harnesses with clear acceptance criteria where local optima
  aren't a concern (e.g. driving lint errors to zero from <50 starting count)
- Short runs (<20 iterations expected)
- When the user wants tight per-iteration oversight anyway

## Output

Save the generated script to `/tmp/run-ralph-<name>.sh` (or user-specified path).
Make it executable. Explain the monitoring commands. For meta-harnesses, save
both layers (`/tmp/run-ralph-<name>.sh` + `/tmp/run-ralph-<name>-meta.sh`).

## Reference Files

For templates and detailed examples, read:
- `reference/template-common.sh` — shared skeleton (all harness types)
- `reference/template-error-reduction.sh` — error count acceptance logic
- `reference/template-performance.sh` — timing + correctness acceptance logic
- `reference/template-code-review.sh` — review iteration acceptance logic
- `reference/template-meta-harness.sh` — outer wrapper for the two-layer pattern

Base directory for this skill: ~/.config/agents/skills/generating-harnesses
