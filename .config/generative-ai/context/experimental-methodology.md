# Experimental Methodology for AI Behavior Problems

When facing persistent AI behavior issues (e.g., not following protocols, skipping steps), use systematic experimentation:

## Process

1. **Research**: Search academic literature for root cause understanding (not just patches)
2. **Hypothesize**: Generate testable hypotheses based on research evidence
3. **Implement**: One variable at a time, version control each experiment
4. **Measure**: Define success criteria, observe systematically, document results
5. **Iterate**: Analyze → refine → implement → measure

## Key Principles

- **Document everything**: Track experiments in structured log (EXPERIMENTS.md)
- **Research first**: Academic papers > blog posts; understand mechanisms, not just techniques
- **Small experiments**: Multiple small changes > one big change (easier to attribute causality)
- **Measure, don't assume**: Count adherence rates, error frequency, etc.

## Research Resources

LLM instruction following challenges:
- "Control Illusion" (arXiv:2502.15851v1) - Instruction hierarchy failures
- "Attention Basin" (arXiv:2508.05128v1) - Positional attention bias
- Key insight: LLMs pay most attention to beginning/end, neglect middle

## Evidence-Based Techniques

- **Position critical info at edges**: Beginning (primacy) or end (recency), not middle
- **Constraint marking**: Explicit labeling ("Step 1:", "Step 2:")
- **Few-shot examples**: 2-5 diverse cases more effective than abstract rules
- **Identity framing**: "You are X who always Y" vs. imperative commands
- **Visual structure**: Heavy delimiters, clear boundaries enhance attention
- **Meta-commentary**: Require explicit confirmation of completion

## When to Use

Good for: Persistent problems, unclear root cause, high-stakes behavior, reusable learning  
Not needed for: One-off issues, well-understood problems, low-impact behaviors

**Example**: ~/indeed/library/PROTOCOL-ADHERENCE-EXPERIMENTS.md documents systematic approach to improving timestamp protocol adherence
