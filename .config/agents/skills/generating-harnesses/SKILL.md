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
  reads the exit reason plus a **wide history window** (last ~1500 state-file
  lines, last ~200 progress lines, AND a compressed list of every prior
  `## Meta cycle` header), then calls amp with a meta prompt. The wide
  default is deliberate: meta reassessment must reason about the strategic
  arc across many cycles, not just this batch — narrow windows produce
  "no signal this batch → Mode-C no-op" errors precisely when intervention
  is most needed. Meta amp picks ONE intervention:
  - **(A) Harness tuning** — edits the inner script (prompt, gates, capture).
    Validated by `bash -n`.
  - **(B) Design seed** — edits the codebase to unblock structural problems.
    Must respect full validation gates (build/lint/correctness checksums) and
    commit + push.
  - **(C) No-op** — records rationale; lets the inner keep climbing.
- Meta skips its amp call on `amp_outage` (sleeps and retries inner) and
  stops if the user removes the inner sentinel.

### Suspicious-short-batch: an inferred signal

The template auto-detects two kinds of "this cycle didn't produce real signal"
events and treats both as triggers for the broader-history framing:

1. **Explicit cycle interrupt**: User removes the inner sentinel while the
   meta sentinel stays. Inner writes `sentinel_removed:` to its exit-reason
   file (with a fallback path that catches removal during the inter-iteration
   sleep). Meta sees the reason and flips `INTERRUPT_MODE=yes`.

2. **Suspicious short batch**: Inner produced ≤2 iterations AND ran <5
   minutes (regardless of exit reason). This is itself evidence that
   "nothing happened this batch" — could be silent interruption, a hung
   amp, an environmental glitch, or just a malformed iteration. The meta
   shouldn't read short batches as "no signal — Mode C"; it should read
   them as "the inner barely had a chance to climb, what's blocking it?"

Both paths set `INTERRUPT_MODE=yes`, which prepends an explicit warning to
the meta prompt:

- "Do NOT default to Mode (C) no-op just because this batch shows little
  signal — that's the failure mode the user is reacting to."
- "Treat the full meta history and progress trajectory as primary evidence,
  not just the most recent few iterations."
- "Strongly prefer Mode (B) design seed or Mode (A) prompt tuning."
- "Mode (C) is allowed only if the long-term arc clearly shows real
  structural progress that would resume with no changes."

The template also ALWAYS includes a "Cross-cycle trajectory" section in
the prompt that requires the meta to sketch the structural-progress
metric across cycles before deciding. This is mode-independent: even on a
healthy full-batch cycle, the meta should reason from the multi-cycle arc,
not just this batch's deltas.

The template tracks `BATCH_ITERS` (lines added to the progress file) and
`BATCH_DURATION` (wall-clock seconds), passes both into `build_meta_prompt`,
and surfaces them in a "This batch's productivity" section so the meta can
quote concrete numbers when reasoning.

### Cross-script contract

- Inner sentinel: `<repo>/.ralph-<name>-continue` (recreated by meta each cycle)
- Meta sentinel: `<repo>/.ralph-<name>-meta-continue`
- Exit reason file: `/tmp/ralph-<name>-exit-reason.txt` (overwritten, not appended)
- State file: `/tmp/ralph-<name>-state.md` (shared — meta appends `## Meta cycle N` sections)
- Lock dirs: separate per layer

### Pair-programming with the meta loop (manual interventions)

The meta loop is not a black box — you (the human pair) can intervene
directly on the harness whenever you spot something the inner agent or
the meta agent is missing. The meta will keep cooperating cleanly if
you record your intervention in a way it can read.

**Pattern: manual meta-cycle entries.** Append a section to the state
file in the same format meta uses, with `manual` in the mode tag:

```
## Meta cycle N — A: manual harness intervention (user-applied, not from amp meta)

**Diagnosis**: <what you noticed>
**Action**: <what you changed, with file paths and line numbers>
**Validation**: <bash -n result, md5 unchanged, etc.>
**Note for next meta cycle**: Strong default to Mode (C) no-op — this
  intervention covers what meta would have done. Override Mode-C only if:
  (a) inner produces N+ rejects citing the new gate criteria,
  (b) <project-specific structural metric> keeps growing without
      <hard-target metric> following,
  (c) inner finds a new gaming pattern.
**Expected next-batch effect**: <what should improve>
```

Replace `N` with the next sequential meta-cycle number (grep
`^## Meta cycle ` in the state file).

**Why this works:**

- The meta prompt grep's all `^## Meta cycle ` headers into
  `meta_history` and includes them in every reassessment, so your manual
  entry appears in the strategic-arc view.
- The Mode-C default with explicit override conditions gives the meta a
  decision rule rather than a vague hint — meta agents are good at
  following rules with concrete triggers.
- The override conditions act as a safety valve: if your fix didn't
  actually address the structural blocker, meta will detect it via the
  cross-cycle trajectory (which is mode-independently required reading)
  and intervene with a complementary action.

**The override path is feature, not bug.** Meta cycles after a manual
intervention have been observed to:
- No-op (most common, when manual fix is sufficient)
- Add a complementary intervention the manual fix didn't address
  (e.g., the manual fix updated the gate; meta then noticed a different
  failure mode the agent was about to mechanically fall into and
  inserted a worked-example seed into the prompt)
- Stay ready to escalate to Mode B if subsequent batches still don't
  produce structural progress

The cycle-interrupt framing (⚠️ "user-requested cycle interrupt — read
broader") is what gives the meta permission to override your "default to
Mode C" — and that's exactly what you want when your local fix turned out
to address only part of the problem.

### Mode B by cherry-pick: salvaging rejected structural commits

When a hill-climber gate rejects a commit for **non-structural reasons**
(cadence cap, helper-investment ceiling, structural-flat-iters limit) but
the commit itself is structurally correct — passes the hard correctness
gates, addresses a previously-named blocker — the meta can salvage it as
a Mode B seed instead of authoring fresh code.

**Recognition signal** (read rejected diffs in the state file):

- All hard correctness gates pass (md5/lint/build/typecheck/test) — the
  agent's diff is sound.
- The reject reason names a *timing* or *budget* constraint, not a
  correctness or spirit issue (e.g., "3rd consecutive coverage-only iter",
  "cluster grew by N > ceiling", "ir_calls didn't grow alongside
  case_drop").
- The commit message or a recent `[crosscase]` reject names a structural
  blocker the diff plausibly addresses.

**Why prefer cherry-pick over authoring a fresh seed**:

- The agent's design has already been validated against the live tree;
  you have higher confidence than a fresh-author seed.
- It's the smallest reversible structural unblock — no scope creep
  beyond what the inner already attempted.
- It preserves productive follow-on work for the next inner batch
  (extending the seeded pattern to other sites is leaf-level work the
  inner does well).

**Mechanism**:

1. `git cherry-pick --no-commit <rejected-sha>` to apply the agent's diff.
2. Re-validate against the harness's hard gates — the cherry-pick
   context may differ from the original (drift between when the agent
   wrote it and when you apply it).
3. Commit with a `[META design seed]` prefix and rationale explaining
   what gate misfired and why the seed is structurally correct.
4. Push if the harness pulls from origin; otherwise leave the commit
   local.

**When NOT to cherry-pick**:

- The rejected commit only addresses a metric, not a named blocker —
  could be a gaming attempt.
- The diff is large enough that you can't be confident it's
  structurally correct without a full review.
- No prior `[crosscase]` or terminal-blocker signal exists — context
  for "this was the right move at the wrong time" is missing.

**Mode A complement**: cherry-pick salvages the work that already
happened; Mode A (relax the gate) lets future iters of the same shape
pass cleanly. Often the right play is both, but for a single-cycle
decision, cherry-pick gives you the structural progress immediately
without a permanent gate change you may regret.

### Mode A by metric tightening: retroactively recognizing gaming

Cherry-pick salvages legitimately-rejected work. The opposite move
exists too: **tightening a metric to retroactively recognize
legitimately-accepted-but-gamed work**. When a "victory" condition
fires (e.g., `classify_cases == 0`) and the codebase is *not* at the
spirit's end state, the proxy was too loose. The remedy is to expand
its definition so the relocated/renamed dispatch logic is counted.

**Recognition signal**:

- A primary metric reaches its target value, but the spirit checklist
  fails (the dispatcher is not actually thin; the IR module does not
  actually own the logic; the codebase is not actually simpler).
- You can spot-grep the codebase and find the dispatch idiom living
  under a syntactic variant the regex didn't match: extracted helpers,
  renamed identifiers (`_br === 'X'` instead of `ref.kind === 'X'`),
  destructured shapes (`const { kind } = ref` then `kind === 'X'`),
  type-narrowing predicates (`isProducerKey(ref)` doing the same job).
- The gamed accepts trace back to anti-patterns #2 (helper extraction)
  or #5 (dispatch renaming), but were not caught at the time because
  the metric's scope or syntactic match was too narrow.

**Mechanism**:

1. Diagnose which syntactic forms host the relocated dispatch. Spot-grep
   for the equivalent idioms (`=== 'lowercaseId'`, predicate calls
   that switch on a discriminator, etc.).
2. Expand the metric: either widen `RALPH_SCOPE_AWK` to capture the
   relocated helpers, or generalize the regex to match the renamed
   form (`=== '[a-z][a-zA-Z]+'` instead of `ref\.kind === '[a-z]'`).
3. Spot-check: run the new metric against the live tree and verify the
   count matches the actual remaining dispatch sites.
4. Document in the meta-cycle entry: "previously-zero count is now N —
   those are the relocated X dispatch checks scattered across {helpers}".
5. Add an explicit anti-pattern note to the inner GOAL: "Do NOT introduce
   more module-scope arrows or rename helpers to evade the new scope —
   the tightened metric counts the dispatcher idiom regardless of where
   it lives."

**Why this is a Mode A intervention, not Mode B**:

- No code changes — only the gate definition shifts.
- The work the inner needs to do does not change in kind, only in
  visibility: the dispatch logic was always there; now the metric
  reflects it.
- The inner can resume immediately on the next iter; no design seed is
  needed.

**Watch for the regret cost**: tightening the metric makes the count
*go up*, which can look like regression and demoralize the loop's
narrative. Frame it explicitly in the meta-cycle entry: "the previous
count was artificially low (gamed); the new count is the honest
measure". The trajectory before the tightening is not invalidated; the
zero-line is just redrawn at a more honest position.

**When to consider tightening prophylactically**: if you can name a
syntactic form the metric *would* miss before the agent finds it,
preempt by widening the scope at design time. The cost of a slightly-
larger metric is much lower than a multi-cycle game-detect-and-tighten
cycle.

### Scope curation: focal-target as a Mode A tool

When the work decomposes into named units (legacy switch arms, error
clusters, modules, files, sub-features) and the agent flits between
them without finishing any, **scope-curation** is a third meta-axis
alongside gate tuning and design seeds. The meta picks ONE target per
batch; the inner is constrained to it; the meta switches targets when
the unit is complete or blocked.

**Mechanism**: a file-based focal-target state.

- File: `/tmp/ralph-<name>-focal-target.txt` (read by inner each iter).
  Empty or missing = no focal constraint (agent operates freely).
  Non-empty = focal target (e.g., `Case 5`, `auth-module`,
  `null-deref-cluster`).
- Inner's `build_prompt` reads the file at iteration time and injects
  a directive: "Your iter MUST be focused on <target>. Other targets
  are forbidden."
- Inner's gate requires commits to be prefixed `[focal:<target>]` when
  the file is non-empty. Mismatch = reject with structured reason.
- Agent can signal needed cross-target work via `[crosscase]` (or
  similar) prefix — that gets rejected too, but the rejection IS the
  signal: if 3+ such rejects pile up, the meta should pivot the focal
  target or escalate to Mode B (the target needs design seeding).

**Why file-based and not env-var or GOAL-baked**:

- File is read fresh each iteration → meta can change focus mid-batch
  without restarting the inner.
- The GOAL string is captured into bash memory at script start, so
  rewriting GOAL requires a restart; file reads don't.
- Persisting the focal target in a file gives the meta a stable
  read-target across reassessments.

**When to use it**:

- Plateau where the structural-progress metric is flat across cycles
  but the leading-indicator metrics keep moving (the wiring-vs-retirement
  gap, but generalized).
- Project decomposes into nameable units that can be completed
  independently in the abstract, even if shared scaffolding is needed
  in practice.

**When NOT to use it**:

- Single-objective harnesses (drive errors to zero) — there's nothing
  to focus on; just one number.
- Refactors where every change touches many units — the constraint
  becomes a barrier rather than a forcing function.
- Early in a run when the problem space is still being explored — the
  meta won't yet know which target is the right one to pick.

**Pivot triggers** (when to change the focal target):

- Target completed (structural metric drops, focal commit acknowledges
  retirement) → pick the next-cheapest unfinished target.
- 3+ consecutive scope-violation rejects → either the target was wrong,
  or the agent has identified a real cross-target dependency. Either
  pivot to a different target or escalate to Mode B.
- Explicit `[crosscase]` commits with stated reasons → likely Mode B
  signal: the target needs design infrastructure the inner agent
  won't introduce.

This pattern is currently used in the RN-2488 harness (the inner-script
focal-case mechanism). The meta-prompt references the file path
explicitly so the meta agent can write to it as a Mode A action.

### Gate-design anti-patterns and remedies (lessons from real runs)

These are recurring failure modes that observable in a hill-climber's
state file. Most surface as "metrics improving but project not actually
advancing" — the agent is rationally mining whatever the gate rewards.

**1. Single-metric gate as code-golf substrate.** Any single gate
criterion (line count, error count, single named metric) eventually
becomes a substrate for cosmetic mining once the easy wins are gone.
Symptom: the chosen metric inches downward across many iters while
no other progress dimension moves. Remedy: require multi-dimensional
progress — the gate should look at 2-3 distinct metrics representing
different phases of the work and require movement on at least one
that ISN'T the easiest one.

**2. Line-count metrics are gameable by line-splitting.** Counting
"lines containing X" or "lines of function Y" lets the agent split
an existing line in two and claim growth/shrinkage. Symptom: a metric
moves but inspecting the diff shows reformatting, not real change.
Remedy: count occurrences of a specific token/pattern via regex
(`grep -cE`), not lines.

**3. Wiring-vs-retirement gap.** When the work has TWO axes — adding
new infrastructure AND retiring the legacy it replaces — agents
strongly prefer the additive axis (adding is safe, deleting is risky).
Symptom: coverage/breadth metrics grow but the metric measuring
"legacy still present" stays flat. Remedy: track both axes explicitly
and gate on both. After N consecutive additive iters, require a
retirement iter. Use distinct commit-message prefixes
(`[coverage]` vs `[demolition]`) so the state file makes the kind
of each iter machine-parseable.

**4. Post-target regime.** Once the primary metric hits a healthy
target, the gate that drove it there becomes a misincentive. Symptom:
`primary_metric < target` is satisfied but agent keeps mining tiny
primary-metric drops, ignoring secondary structural progress.
Remedy: add a threshold conditional to the gate — "if `primary < X`,
require structural progress (other metric must move)".

**5. `STRUCTURAL_FLAT_ITERS` cap.** A general-purpose counter that
tracks consecutive accepted iters without movement on the
structural-progress metric (whatever the project's "real progress"
metric is — case count, retirement count, milestone). Reject the
N+1th iter and force the agent to engage with the structural axis.
This is the most reusable single mechanic — combined with multi-axis
metrics, it prevents most code-golf failure modes.

**6. Commit-prefix protocols.** Require the agent to prefix commit
messages by the kind of work the iter represents (`[coverage]`,
`[demolition]`, `[infra]`, `[refactor]`). Makes the state file
self-classifying for the meta agent and gives the inner agent a
forced-articulation step that often surfaces "this commit doesn't
actually fit any category" before the agent commits.

**7. Mode A vs Mode B in practice.** When the meta diagnoses a
plateau, Mode A (gate/prompt tuning) is preferable when the structural
infrastructure exists but the agent isn't using it. Mode B (design
seed) is for when the structural piece is genuinely missing and an
inner agent — focused on small leaf moves — won't introduce it.
The signature of "should be A": prompt already names the structural
target, but the gate doesn't reward it. The signature of "should be B":
no prior iters even attempt the structural target.

**8. Scope evasion via refactor primitives.** A more adversarial form
of #1: when the metric is computed by scanning a function (e.g.,
`awk '/^function foo/,/^}$/' | grep -cE '...'`), the agent can extract
HELPERS outside the function whose bodies host the same dispatch
patterns. The metric reads zero; the dispatch logic is intact, just
relocated. Symptom: metric drops sharply with `[refactor]`/`[extract]`
commits while no IR/test/correctness signal moves; downstream meta
cycles eventually catch the discrepancy when the agent runs out of
non-tested progress. Remedy: scope the metric across the entire file
or module, not a single function — the agent can still extract
helpers, but the metric continues to count their dispatch patterns
wherever they live. Even better: track the metric over a *type-system*
or *AST* scope (e.g., "discriminator unions remaining") that's
refactor-stable.

**9. Subsumption-via-compression mismodeled by anti-gaming gates.**
Anti-gaming rules of the shape `case_drop > 0 AND ir_growth < case_drop
AND lines_drop < 2*case_drop → reject` (designed to catch syntactic
switch→if/else rewrites, anti-pattern #1) misfire on legitimate
**subsumption-via-compression**: where N per-kind dispatchers collapse
into a single IR call whose `compile` already handles each variant.
In subsumption, `ir_growth` can go *negative* (5 dispatcher calls →
1 unified call) AND `lines_drop` is modest (a dense dispatch chain
becomes one line, saving ~N lines, not 2N). Symptom: the agent
explicitly anticipates the misfire ("subsumption naturally compresses
ir_calls — this won't fit the gate's growth-only model") and the gate
indeed rejects a structurally-correct iter. Remedy: model
subsumption as a third demolition shape alongside pure-routing
(`ir_growth ≥ case_drop`) and pure-deletion (`lines_drop ≥ 2*case_drop`).
A practical rule: accept when `case_drop > 0 AND lines_drop ≥ case_drop
AND prior ir_coverage already covers the dropped kinds`. The
last conjunct is the key — it ensures the dropped dispatchers had a
real IR replacement set up in earlier coverage iters, distinguishing
subsumption from anti-pattern #1's syntactic rewrite. Watch for the
agent narrating the gap in advance: when an inner output names the
gate-model gap before the rejection, that's high-signal — a Mode A
gate extension is usually the right next move.

### The Goodhart trap: metrics need intent framing

Every anti-pattern above is a manifestation of the same root issue:
**prompts that frame the work as metric-satisfaction induce metric-
gaming.** When the agent's only optimization signal is "make these
numbers move", it will find ways to move the numbers that don't
advance the actual goal. Tightening the metric closes one loophole
and the agent finds another. Eventually you're spending more
iterations playing whack-a-mole than doing the real work.

The remedy is to write GOAL prompts that name **the spirit of the
work** in terms the agent can evaluate alongside the metrics, not
just the metrics in isolation:

- ❌ Metric-only: "classify_lines MUST decrease. classify_cases MUST
  NOT increase. ir_calls growth is rewarded."
- ✅ Spirit + metric: "The end state is that classifySxExpression is a
  thin dispatcher and the IR module owns all transformation logic. The
  legacy ad-hoc dispatch is gone. Your iter is real progress if it
  moves the codebase toward that end state — not if it merely satisfies
  the numeric gates. Helper extraction that relocates dispatch logic
  to satisfy a regex is NOT real progress; the gate may accept it but
  the meta will catch it. The metrics below approximate progress; when
  in doubt, ask 'is the codebase simpler/more typed/more testable than
  before?' and use that as the tiebreaker."

**Why this works**: agent post-training is reasonably good at
"evaluate this code change against this stated goal" when the goal is
articulated with concrete end-state criteria. It's much less good at
"satisfy this metric without gaming it" because agents have generalized
strategies for satisfying metrics that don't always coincide with what
the principal wants.

**Practical recipe for prompt structure**:

1. **Spirit (3-5 sentences)**: name the end state, the principal's
   actual goal, and what "real progress" vs. "fake progress" looks
   like in concrete terms.
2. **Hard guardrails (must-pass)**: things that always reject —
   correctness invariants, build/lint/test, never-go-backward
   constraints. These are uncontroversial; agents don't game them
   because they're impossible to satisfy without doing them.
3. **Acceptance regime (priority-ordered)**: the metrics, framed as
   approximations of the spirit, with explicit acknowledgment that the
   metrics are imperfect. Include "if your iter satisfies a metric but
   doesn't match the spirit, the meta will catch it" as a deterrent.
4. **Anti-pattern callouts**: name the gaming patterns you've seen and
   warn against them explicitly. "Do not extract helpers solely to
   evade the regex. Do not split lines to grow occurrence counts." This
   is more effective than just tightening the gate, because it gives
   the agent explicit knowledge of what counts as gaming.

The metric-vs-spirit balance is fundamentally about epistemic respect
for the agent: the meta loop assumes the agent will rationally follow
incentives, including misaligned ones, so the prompt should make the
true incentive (the spirit) just as legible as the proxy incentives
(the metrics). Without the spirit, the agent has nothing to fall back
on when the metrics produce ambiguous signals — and gaming becomes
the path of least resistance.

**Validation signal: agent self-correction.** When the recipe is
working, you'll see the inner *retry* a rejected anti-pattern with a
real version on the next iter. Example from the RN-2488 run: iter 7
was a `case_drop=1, ir_growth=0, lines_drop=0` syntactic switch→if/else
rewrite (anti-pattern #1), rejected with that reason quoted in the
state file. Iter 8 produced the same retirement target as a real
deletion (`case_drop=1, lines_drop=2`) — the agent read the reject
reason, recognized which anti-pattern fired, and re-attempted with a
spirit-aligned move *without any meta intervention*. This is what
"epistemic respect" looks like in practice: clear anti-pattern names
in the prompt + clear anti-pattern callouts in the rejection messages
let the agent self-correct without further harness work. If you see
this pattern, the prompt is doing its job; if you don't, the rejection
messages probably aren't naming the anti-pattern explicitly enough.

### Forced articulation: making the agent justify its iter

Mechanical metrics are cheap to evaluate but easy to game. LLM-as-judge
is hard to game but expensive (doubles per-iter cost) and adds variance.
**Forced articulation** is a near-zero-cost middle ground: require the
agent's commit message to contain explicit answers to spirit-aligned
questions before committing.

The pattern: append a "Pre-commit articulation (REQUIRED)" section to
the GOAL prompt that requires three short paragraphs in every commit
message body:

1. **Spirit advanced** — 1-3 sentences naming which spirit criterion
   this iter moves toward, with concrete reference to the change
   (which symbol, which line range, which legacy structure went away).
2. **Anti-pattern check** — 1-2 sentences naming which anti-pattern
   this iter MIGHT look like and why it isn't. If the agent can't
   construct a plausible "this might look like #N because..." sentence,
   it's a signal that the agent isn't engaging with the anti-pattern
   list.
3. **Next iter** — 1 sentence naming the natural follow-up move. If
   the agent can't name a follow-up, the iter may be a dead-end and
   they should reconsider scope.

**Why this works**:

- Agents reliably struggle to write coherent justification for fake
  progress. A vague "Spirit advanced: this makes things better" is
  itself a signal — the meta can read it as "agent could not name a
  concrete advance".
- Costs nothing extra (no judge LLM call). The agent already writes a
  commit message; this just constrains its shape.
- Captured in git history. The meta sees these on every cycle without
  any extra plumbing — `git log` already exposes them.
- Forces the agent to pre-empt the meta's evaluation. Articulating
  "this might look like anti-pattern #N because..." in advance is
  cheaper than the meta detecting it after the fact.

**When forced articulation alone isn't enough**:

- Agent writes formulaic boilerplate to satisfy the requirement
  without engaging. Symptom: every iter says "Spirit advanced: moves
  toward thin dispatcher" verbatim. Remedy: tighten the requirement
  ("be concrete: name the symbol, the line range, the legacy structure
  that went away") and have the meta flag iters with low articulation
  variance.
- The agent's articulation is honest but the meta can't act on it
  fast enough. This is the cycle-length problem; see below.

**Escalation order** when forced articulation isn't sufficient:

1. **Tighten the articulation requirement** (free, fastest).
2. **Suspicious-pattern triggered judge** — LLM judge runs only on
   accepts where heuristics fire (case_drop > ir_growth, large
   `[refactor]`, ceiling-adjacent). Concentrates LLM cost on
   high-risk decisions.
3. **Judge-as-commentary** — LLM judge produces a one-line annotation
   on each accept ("looks like genuine subsumption" / "looks like #1
   syntactic rewrite"). Doesn't gate; feeds the meta richer signal.
4. **Per-iter LLM judge** — most expensive, highest variance. Only if
   1-3 are insufficient. Note: the judge becomes the new metric to
   game; you've shifted the gaming target rather than eliminated it.

The default position should be "forced articulation + meta layer".
The meta IS already an LLM judge; it just runs every N iters instead
of every iter. The cost amortization is favorable when N is right —
which means the right escalation often isn't a per-iter judge but
**adjusting the meta cycle length** (see next).

### Cycle length as a Mode A lever

When the meta is correctly diagnosing gaming or misalignment but the
correction comes too late (the inner has already accumulated N gamed
accepts before the meta intervenes), the answer is often *not* to add
a per-iter judge — it's to shorten the meta cycle.

Make `INNER_ITERATIONS_PER_CYCLE` (or equivalent) **adjustable
mid-run** without restarting the meta loop:

- Read the value from a file (e.g., `/tmp/ralph-<name>-inner-iters.txt`)
  at the top of each meta cycle, with sane bounds (e.g., 1-100) and a
  fallback to the env-var default.
- Make this an explicit Mode A action in the meta's decision tree.
- Document write-targets in the meta prompt so the meta agent knows
  the file path.

**Shorten when**:

- Iters look gamed and you want faster correction (more meta cycles
  per unit of inner work).
- The inner is in an exploratory phase where you want tight oversight.
- A prior cycle made a Mode B seed and you want to verify the inner
  consumes it cleanly before committing many iters to a possibly-wrong
  path.

**Lengthen when**:

- The inner is making consistent honest structural progress and meta
  intervention is mostly Mode C no-op.
- Inner iters are slow and per-cycle wall-clock cost is dominated by
  meta overhead.
- The work has entered a mechanical-extension phase where each iter is
  a small variation on the prior, with low risk of gaming.

**Why file-based, not env-var or harness edit**:

- Env-var requires a meta restart. File is hot.
- Harness-edit (changing the script) is a heavier intervention with a
  larger blast radius. File-based is targeted.
- Same design rationale as the focal-target file (read fresh per cycle,
  no restart needed).

**Implementation sketch** (bash):

```bash
# Top of each meta cycle:
if [ -s "$INNER_ITERS_FILE" ]; then
    FILE_ITERS=$(tr -d '[:space:]' < "$INNER_ITERS_FILE")
    if [[ "$FILE_ITERS" =~ ^[0-9]+$ ]] && [ "$FILE_ITERS" -ge 1 ] && [ "$FILE_ITERS" -le 100 ]; then
        INNER_ITERATIONS_PER_CYCLE="$FILE_ITERS"
    fi
fi
```

Cycle-length adjustment is the cheapest scaling lever for catching
gaming faster. Reach for it before reaching for a per-iter LLM judge.

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
