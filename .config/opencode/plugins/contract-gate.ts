// ~/.config/opencode/plugins/contract-gate.ts
//
// Contract gate for panel subagents.
//
// Fires after each `task` tool call whose subagent_type is a contract-bound
// role (design / plan-impl / critic, any model variant). It locates the
// deliverable file the subagent was told to write (path named in the task
// prompt, cross-checked against files the subagent actually wrote), checks
// the required "##" headers (in order, code fences stripped) AND the per-role
// minimum line count, and on failure asks the SAME subagent session to fix it
// once (reorganize for missing headers; expand with substance for too-short).
// The orchestrator only sees a longer task call — the retry is transparent.
//
// Policy: one revision round, then annotate FORMAT-CHECK-FAILED (with the
// real reason: missing headers and/or too short) so the orchestrator drops
// the member to N-1 and records that reason verbatim.
//
// Non-fatal by design: any internal error is logged and the original output
// is returned untouched.
//
// Audit log: /tmp/contract-gate.log
//
// Usage: drop in ~/.config/opencode/plugins/ and restart OpenCode.

import { existsSync, readFileSync, appendFileSync } from "node:fs";

const LOG_FILE = process.env.CONTRACT_GATE_LOG || "/tmp/contract-gate.log";

function log(msg: string) {
  const line = `[${new Date().toISOString()}] [contract-gate] ${msg}\n`;
  try {
    appendFileSync(LOG_FILE, line);
  } catch {}
  console.log(`[contract-gate] ${msg}`);
}

// ---------- contracts ----------

// Required "##" headers per role, in order.
const CONTRACTS: Record<string, string[]> = {
  design: [
    "Premise Questions",
    "Problem Reframe",
    "Options Explored",
    "Tradeoff Analysis",
    "Recommendation",
    "Open Questions",
    "Alternatives Considered",
    "Self-Review Notes",
  ],
  "plan-impl": [
    "Premise Questions",
    "Goal",
    "Scope",
    "Prerequisites",
    "Steps",
    "Checkpoints",
    "Risks",
    "Alternatives Considered",
    "Self-Review Notes",
  ],
  critic: ["Strengths", "Issues", "Edge Cases", "Suggestions", "Verdict"],
};

// Per-role minimum line counts — MUST match check_contract.py MIN_LINES.
// The plugin enforces this in-session (first line of defense); the script is
// the final gate. Counted on the raw text (fences included), like the script.
const MIN_LINES: Record<string, number> = { design: 100, "plan-impl": 80, critic: 40 };

// Agent names are "<role>" or "<role>-<model>" (e.g. design-gemma).
const MODEL_SUFFIXES = ["gemma", "nemotron", "muse", "qwen"];

function contractFor(agent: string): string[] | undefined {
  if (CONTRACTS[agent]) return CONTRACTS[agent];
  for (const s of MODEL_SUFFIXES) {
    if (agent.endsWith(`-${s}`)) {
      const base = agent.slice(0, -(s.length + 1));
      if (CONTRACTS[base]) return CONTRACTS[base];
    }
  }
  return undefined;
}

// Base role ("design" | "plan-impl" | "critic") for an agent name.
function roleFor(agent: string): string | undefined {
  if (CONTRACTS[agent]) return agent;
  for (const s of MODEL_SUFFIXES) {
    if (agent.endsWith(`-${s}`)) {
      const base = agent.slice(0, -(s.length + 1));
      if (CONTRACTS[base]) return base;
    }
  }
  return undefined;
}

// ---------- shape check ----------

// Strip fenced code blocks so example headers inside code don't count.
function stripFences(text: string): string {
  const out: string[] = [];
  let open: string | null = null;
  for (const line of text.split("\n")) {
    const m = line.match(/^\s*(`{3,}|~{3,})/);
    if (m) {
      const ch = m[1][0];
      if (!open) open = ch;
      else if (ch === open) open = null;
      continue;
    }
    if (!open) out.push(line);
  }
  return out.join("\n");
}

// Required headers must appear as "## Header" lines, in order (subsequence).
// Extra top-level sections are allowed (e.g. critic context sections).
function checkContract(text: string, headers: string[]): { ok: boolean; missing: string[] } {
  const found: string[] = [];
  for (const line of stripFences(text).split("\n")) {
    const m = line.match(/^##\s+(.+?)\s*$/);
    if (m) found.push(m[1]);
  }
  const missing: string[] = [];
  let i = 0;
  for (const h of headers) {
    let idx = -1;
    for (let j = i; j < found.length; j++) {
      if (found[j] === h) {
        idx = j;
        break;
      }
    }
    if (idx === -1) missing.push(h);
    else i = idx + 1;
  }
  return { ok: missing.length === 0, missing };
}

// Line count matching Python's str.splitlines() on the raw text (fences
// included): a trailing newline does not add an extra line.
function countLines(text: string): number {
  const lines = text.split(/\r\n|\r|\n/);
  if (lines.length > 0 && lines[lines.length - 1] === "") lines.pop();
  return lines.length;
}

// ---------- deliverable location ----------

// .md files the subagent wrote during its session (write/edit tool calls), in order.
async function writtenMdFiles(client: any, sessionId: string): Promise<string[]> {
  const res = await client.session.messages({ path: { id: sessionId } });
  const files: string[] = [];
  for (const msg of res.data ?? []) {
    for (const part of msg.parts ?? []) {
      if (part?.type === "tool" && (part.tool === "write" || part.tool === "edit")) {
        const p = part.state?.input?.filePath;
        if (typeof p === "string" && p.endsWith(".md")) files.push(p);
      }
    }
  }
  return files;
}

// Last non-empty text part of the subagent session (fallback deliverable).
async function lastTextPart(client: any, sessionId: string): Promise<string | undefined> {
  const res = await client.session.messages({ path: { id: sessionId } });
  const msgs = res.data ?? [];
  for (let i = msgs.length - 1; i >= 0; i--) {
    for (const part of msgs[i].parts ?? []) {
      if (part?.type === "text" && typeof part.text === "string" && part.text.trim()) return part.text;
    }
  }
  return undefined;
}

// The task prompt names the output file(s); the last absolute .md path is the deliverable.
function pathFromPrompt(prompt: string): string | undefined {
  const all = prompt.match(/\/[^\s`'"|),;]+\.md/g);
  return all ? all[all.length - 1] : undefined;
}

// ---------- plugin ----------

export const ContractGate = async ({ client }: { client: any }) => {
  log("loaded");

  return {
    "tool.execute.after": async (input: any, output: any) => {
      if (input.tool !== "task") return;
      const agent = typeof input.args?.subagent_type === "string" ? input.args.subagent_type : undefined;
      const contract = agent ? contractFor(agent) : undefined;
      const sessionId =
        typeof output.metadata?.sessionId === "string" ? output.metadata.sessionId : undefined;
      if (!contract || !sessionId) return;
      if (typeof output.output !== "string") return;

      try {
        const promptText = typeof input.args?.prompt === "string" ? input.args.prompt : "";
        const named = pathFromPrompt(promptText);

        // Locate the deliverable: prefer the prompt-named path if the agent
        // actually wrote it; else the last .md the agent wrote; else the
        // prompt-named path (the revision will instruct writing there).
        const written = await writtenMdFiles(client, sessionId);
        let file: string | undefined;
        if (named && written.includes(named)) file = named;
        else if (written.length) file = written[written.length - 1];
        else if (named) file = named;

        let text =
          file && existsSync(file) ? readFileSync(file, "utf8") : await lastTextPart(client, sessionId);
        if (!text) {
          log(`no deliverable found for ${agent} (${sessionId}); skipping`);
          return;
        }

        const role = roleFor(agent);
        const minLines = role ? MIN_LINES[role] : 0;
        const nLines = countLines(text);
        const shape = checkContract(text, contract);
        const tooShort = minLines > 0 && nLines < minLines;
        if (shape.ok && !tooShort) {
          log(`PASS ${agent} ${sessionId} file=${file ?? "inline"} lines=${nLines}`);
          return;
        }

        const problems: string[] = [];
        if (!shape.ok) problems.push(`missing/out-of-order headers: ${shape.missing.join(", ")}`);
        if (tooShort) problems.push(`too short: ${nLines} lines < ${minLines} minimum`);
        log(`FAIL ${agent} ${sessionId} file=${file ?? "inline"} ${problems.join("; ")}`);

        // One revision round, in the same subagent session (blocking).
        // Addresses header failures AND a too-short document in the same pass.
        const target = file ?? `/tmp/contract-gate/${sessionId}.md`;
        const revision: string[] = [
          "FORMAT CHECK FAILED. Your deliverable does not match the required contract.",
          "",
          `The document MUST contain exactly these ${contract.length} sections, in this order, with these exact "##" header names:`,
          ...contract.map((h, i) => `${i + 1}. ## ${h}`),
          "",
        ];
        if (!shape.ok) {
          revision.push(`Currently missing or out of order: ${shape.missing.join(", ")}`, "");
        }
        if (tooShort) {
          revision.push(
            `The document is also too short: ${nLines} lines, but it must be at least ${minLines} lines.`,
            "Expand it with concrete, specific substance — real details, examples, tradeoffs, edge cases, and rationale — spread across the required sections. Do not pad with filler or restate the same point; add genuine depth.",
            "",
          );
        }
        revision.push(
          `Rewrite the COMPLETE document to exactly this path: ${target}`,
          'Keep exactly the required top-level sections (no others). Where a section has nothing to add, write "N/A".',
        );

        await client.session.prompt({
          path: { id: sessionId },
          body: { agent, parts: [{ type: "text", text: revision.join("\n") }] },
        });

        // Re-locate: the agent may have written a new file during revision.
        const written2 = await writtenMdFiles(client, sessionId);
        const file2 = written2[written2.length - 1] ?? target;
        const text2 = existsSync(file2) ? readFileSync(file2, "utf8") : await lastTextPart(client, sessionId);
        const shape2 = text2 ? checkContract(text2, contract) : { ok: false, missing: contract };
        const nLines2 = text2 ? countLines(text2) : 0;
        const tooShort2 = minLines > 0 && nLines2 < minLines;

        if (shape2.ok && !tooShort2) {
          output.output += `\n\n[contract-gate] initial check failed (${problems.join(
            "; ",
          )}); one in-session revision requested — output now conforms at ${file2} (${nLines2} lines).`;
          log(`PASS(after revision) ${agent} ${sessionId} file=${file2} lines=${nLines2}`);
        } else {
          const problems2: string[] = [];
          if (!shape2.ok) problems2.push(`missing/out-of-order headers: ${shape2.missing.join(", ")}`);
          if (tooShort2) problems2.push(`too short: ${nLines2} lines < ${minLines} minimum`);
          output.output += `\n\n[contract-gate] FORMAT-CHECK-FAILED: still non-conformant after 1 revision (${problems2.join(
            "; ",
          )}). Drop this panel member (N-1) and record THIS reason verbatim — do not invent a different cause.`;
          log(`FAIL(after revision) ${agent} ${sessionId} file=${file2} ${problems2.join("; ")}`);
        }
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        log(`ERROR ${agent ?? "?"} ${sessionId ?? "?"}: ${msg}`);
        output.output += `\n\n[contract-gate] check error (non-fatal, original output returned): ${msg}`;
      }
    },
  };
};
