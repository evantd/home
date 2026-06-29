// ~/.config/opencode/plugins/repetition-detector.js
//
// Detects model repetition loops and injects corrective messages.
// Catches four patterns:
//   1) Consecutive text similarity (same point restated verbatim)
//   2) Tool call cycle detection (same sequence of tools repeated across turns)
//   3) Repeated tool calls within a single message
//   4) Cross-turn single-tool repetition (same tool called N+ times consecutively)
//
// Conservative defaults to avoid false positives. Tune via env vars.
//
// Usage: Drop in ~/.config/opencode/plugins/ and restart OpenCode.
// Optional env vars:
//   REPETITION_THRESHOLD=0.7      — n-gram overlap threshold (default 0.7 = 70%)
//   REPETITION_MIN_LENGTH=200     — skip short responses for text check (default 200 chars)
//   REPETITION_TOOL_CYCLE=3       — min tools in a cycle to detect (default 3)
//   REPETITION_SINGLE_TOOL=3      — same single tool repeated across turns (default 3)
//   REPETITION_COOLDOWN=60        — seconds between corrections (default 60)
//   REPETITION_LOG_FILE=~/.config/opencode/repetition.log  — log file path

const THRESHOLD = parseFloat(process.env.REPETITION_THRESHOLD) || 0.7;
const MIN_LENGTH = parseInt(process.env.REPETITION_MIN_LENGTH) || 200;
const TOOL_CYCLE_MIN = parseInt(process.env.REPETITION_TOOL_CYCLE) || 3;
const SINGLE_TOOL_REPETITION = parseInt(process.env.REPETITION_SINGLE_TOOL) || 3;
const COOLDOWN = parseInt(process.env.REPETITION_COOLDOWN) || 60;
const LOG_FILE = process.env.REPETITION_LOG_FILE || "~/.config/opencode/repetition.log";

// Resolve ~ in path
const logPath = LOG_FILE.startsWith("~")
  ? require("path").join(require("os").homedir(), LOG_FILE.slice(1))
  : LOG_FILE;

let lastCorrectionTime = 0;

function log(...args) {
  const line = `[${new Date().toISOString()}] [repetition-detector] ${args.join(" ")}\n`;
  require("fs").appendFileSync(logPath, line);
}

// ---------- helpers ----------

function getNgrams(text, n = 3) {
  const words = text.toLowerCase().split(/\s+/).filter(w => w.length > 0);
  const ngrams = new Set();
  for (let i = 0; i <= Math.max(0, words.length - n); i++) {
    ngrams.add(words.slice(i, i + n).join(" "));
  }
  return ngrams;
}

function jaccard(a, b) {
  if (a.size === 0 && b.size === 0) return 0;
  const inter = new Set([...a].filter(x => b.has(x)));
  const union = new Set([...a, ...b]);
  return inter.size / union.size;
}

function extractToolFingerprint(parts) {
  const toolCalls = [];
  for (const part of parts || []) {
    if (part.type === "tool_use") {
      // Capture both name and arguments for more precise matching
      toolCalls.push({
        name: part.name,
        input: JSON.stringify(part.input || {})
      });
    }
  }
  return toolCalls;
}

// ---------- state ----------

let assistantHistory = [];

export const RepetitionDetector = async ({ client }) => {
  log(`initialized (threshold: ${THRESHOLD}, min_length: ${MIN_LENGTH}, cooldown: ${COOLDOWN}s, single_tool_repetition: ${SINGLE_TOOL_REPETITION})`);

  return {
    "message.updated": async ({ message }) => {
      if (message.role !== "assistant") return;

      const textParts = message.parts?.filter(p => p.type === "text") || [];
      const text = textParts.map(p => p.text).join("\n").trim();
      const toolCalls = extractToolFingerprint(message.parts);

      // DEBUG: log what we're seeing
      log(`msg: text_len=${text.length}, tool_calls=${toolCalls.length}, parts=${(message.parts||[]).length}`);
      if (toolCalls.length > 0) {
        toolCalls.forEach(tc => log(`  tool: ${tc.name} input=${tc.input.substring(0,100)}`));
      }

      // Check cooldown before anything else (but still track for detection)
      const now = Date.now();
      const inCooldown = now - lastCorrectionTime < COOLDOWN * 1000;

      const entry = { text, toolCalls, timestamp: now };
      assistantHistory.push(entry);

      // Keep last 6 messages (wider window for cross-turn detection)
      while (assistantHistory.length > 6) assistantHistory.shift();

      if (assistantHistory.length < 2) return;

      const current = assistantHistory[assistantHistory.length - 1];
      const prev = assistantHistory[assistantHistory.length - 2];
      let reason = null;

      // --- Check 1: Consecutive text similarity ---
      // Only applies when both messages meet MIN_LENGTH threshold
      if (text.length >= MIN_LENGTH && prev.text.length >= MIN_LENGTH) {
        const curNgrams = getNgrams(current.text);
        const prevNgrams = getNgrams(prev.text);
        const sim = jaccard(curNgrams, prevNgrams);

        if (sim >= THRESHOLD) {
          reason = `text overlap ${(sim * 100).toFixed(0)}%`;
          log(`text similarity: ${sim.toFixed(2)}`);
        }
      }

      // --- Check 2: Tool call cycle (same sequence of tools repeated across turns) ---
      if (!reason && toolCalls.length >= TOOL_CYCLE_MIN) {
        const recentTools = assistantHistory
          .map(e => e.toolCalls.map(t => t.name).join(","))
          .filter(Boolean);

        if (recentTools.length >= 2) {
          const lastCycle = recentTools[recentTools.length - 1];
          for (let i = 0; i < recentTools.length - 1; i++) {
            if (recentTools[i] === lastCycle && i < recentTools.length - 2) {
              reason = `tool cycle: ${lastCycle} repeated`;
              log(`tool cycle detected: ${lastCycle}`);
              break;
            }
          }
        }
      }

      // --- Check 3: Repeated tool calls within a single message ---
      if (!reason && toolCalls.length >= 2) {
        const uniqueTools = new Set(toolCalls.map(t => t.name));
        if (uniqueTools.size < toolCalls.length * 0.6) {
          reason = `repeated tool calls in one response`;
          log(`within-message repetition: ${toolCalls.length} calls, ${uniqueTools.size} unique`);
        }
      }

      // --- Check 4: Cross-turn single-tool repetition ---
      // Detects when the same tool with similar arguments is called consecutively
      if (!reason && toolCalls.length >= 1) {
        const currentTool = toolCalls[0];
        let consecutiveCount = 1;

        // Count backwards through history for consecutive same-tool calls
        for (let i = assistantHistory.length - 2; i >= 0; i--) {
          const histEntry = assistantHistory[i];
          if (histEntry.toolCalls.length >= 1) {
            const histTool = histEntry.toolCalls[0];
            // Match by name and similar arguments (80%+ overlap)
            if (histTool.name === currentTool.name) {
              const argSim = jaccard(
                getNgrams(histTool.input, 2),
                getNgrams(currentTool.input, 2)
              );
              if (argSim >= 0.8 || histTool.input === currentTool.input) {
                consecutiveCount++;
              } else {
                break; // Different arguments, stop counting
              }
            } else {
              break; // Different tool, stop counting
            }
          } else {
            break; // No tools in history entry, stop counting
          }
        }

        if (consecutiveCount >= SINGLE_TOOL_REPETITION) {
          reason = `same tool repeated ${consecutiveCount} times: ${currentTool.name}`;
          log(`cross-turn repetition: ${consecutiveCount} consecutive calls to ${currentTool.name}`);
        }
      }

      // --- Check 5: Repeated bash commands ---
      // Detects when the same bash command is run multiple times consecutively
      if (!reason) {
        const bashPattern = /^bash:/i;
        const currentBash = toolCalls.find(tc => bashPattern.test(tc.name));
        if (currentBash) {
          let consecutiveBash = 1;
          for (let i = assistantHistory.length - 2; i >= 0; i--) {
            const histEntry = assistantHistory[i];
            const histBash = histEntry.toolCalls.find(tc => bashPattern.test(tc.name));
            if (histBash && histBash.input === currentBash.input) {
              consecutiveBash++;
            } else {
              break;
            }
          }
          if (consecutiveBash >= 2) {
            reason = `same bash command repeated ${consecutiveBash} times`;
            log(`bash repetition: ${consecutiveBash} consecutive identical bash commands`);
          }
        }
      }

      // --- Act ---
      if (reason) {
        log(`REPETITION DETECTED: ${reason}`);
        lastCorrectionTime = now;

        const correctionText = `[System] Repetition detected: ${reason}. Stop repeating yourself. Either the previous attempt failed for a reason you need to address, or you need to take a different approach entirely.`;

        try {
          await client.session.prompt({
            noReply: true,
            parts: [{ type: "text", text: correctionText }]
          });
          log("correction injected");
        } catch (err) {
          log(`Failed to inject correction: ${err.message}`);
        }
      } else if (assistantHistory.length >= 2) {
        // Fresh turn — clear window if similarity is very low
        const curNgrams = getNgrams(current.text);
        const prevNgrams = getNgrams(prev.text);
        const sim = jaccard(curNgrams, prevNgrams);
        if (sim < 0.15) {
          log("fresh turn — clearing history window");
          assistantHistory.length = 1;
        }
      }
    }
  };
};
