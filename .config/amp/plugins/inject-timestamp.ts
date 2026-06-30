import type { PluginAPI } from '@ampcode/plugin'
import { appendFile, mkdir } from 'node:fs/promises'
import {
  closeSync,
  openSync,
  writeSync,
  readFileSync,
  writeFileSync,
  mkdirSync,
  renameSync,
} from 'node:fs'
import { execSync, execFileSync } from 'node:child_process'
import { dirname } from 'node:path'
import { homedir } from 'node:os'

/**
 * Inject the current wall-clock time into each user turn so the agent has
 * grounded temporal context, AND log deterministic agent/tool timing events
 * for offline analysis.
 *
 * Three streams to ~/indeed/library/logs/:
 *   - turn-times.jsonl: agent.start / agent.end (per-turn brackets)
 *   - tool-times.jsonl: tool.call / tool.result (per-tool brackets)
 *
 * Pair entries by message_id (turns) or toolUseID (tools). Use
 * scripts/analyze_turn_timing.py to decompose each turn into:
 *   - tool I/O time (sum of tool.result - tool.call)
 *   - agent thinking time (turn duration - tool time)
 *   - user gap time (next agent.start - prior agent.end)
 *
 * Why two files: tool events would dominate turn-times line counts. Splitting
 * keeps the small-file analysis fast and avoids forcing every consumer to
 * filter by event type.
 */

const TURN_LOG = `${homedir()}/indeed/library/logs/turn-times.jsonl`
const TOOL_LOG = `${homedir()}/indeed/library/logs/tool-times.jsonl`

/**
 * Transition-log capture — a two-layer design that does NOT depend on model
 * compliance. The standing `log-transition` mandate in ~/.config/AGENTS.md
 * became unreliable across all threads (~2026-06-18): the model stopped obeying
 * a rule buried in a large always-on guidance file. We then tried an in-turn
 * reminder (below), but that ALSO proved skippable — on 2026-06-29 a single
 * thread ignored a fired reminder, "verified" the command without running it,
 * and went on a discovery dance — because an injected reminder still competes
 * with the user's explicit ask and loses. Instructions are obeyed only
 * probabilistically; reliable capture must not rely on them.
 *
 * Three-step escalation, each step needed only when the previous is ignored:
 *
 *  Step 1 (quality): at agent.start of a "cold" turn, inject a strong,
 *  self-contained reminder (with the exact `~/bin/log-transition "..."` command)
 *  so the MODEL writes a meaningful note when it complies.
 *
 *  Step 2 (focused retry): at agent.end, if the cold turn finished without the
 *  model running `log-transition`, return a `continue` follow-up turn whose
 *  ONLY instruction is to run the command — no competing task to distract from
 *  it. This still yields a model-written (quality) note. The follow-up carries
 *  LOG_REQUEST_MARKER so it's recognized and never spawns another continue.
 *
 *  Step 3 (guarantee): if even the focused follow-up turn doesn't run the
 *  command, the plugin writes a deterministic note itself (timestamp +
 *  truncated user prompt + thread link, prefixed `[auto]`). Capture never
 *  depends on model compliance; the `[auto]` tag makes lapses visible on review.
 *
 * Compliance is detected by scanning the turn's tool calls for a
 * `log-transition` shell command via amp.helpers (no fragile file diffing).
 *
 * "Cold" trigger: a thread is brand-new or idle ≥ GAP_THRESHOLD_MS since its
 * own last turn. Per-thread (not global) because the user runs many concurrent
 * threads: a global "time since any turn" clock would never register an
 * individual thread going idle. A new thread and a long-idle thread get the
 * SAME generic reminder; the model reads the <current-time> markers across
 * turns to judge how much time (if any) actually passed.
 *
 * State: a small JSON map of threadId -> last-activity ISO timestamp, durable
 * across CLI processes. "Cold" = absent OR stale (>= threshold). Correctness
 * comes from the read-time staleness check, NOT from pruning — pruning only
 * runs on writes, so a returning thread may still have a stale entry present.
 * The prune (at the same threshold) is just housekeeping to keep the file tiny:
 * it holds only threads active within the last GAP_THRESHOLD_MS.
 *
 * The cold flag for the in-flight turn is held in an in-memory map (set at
 * agent.start, consumed at agent.end). agent.start and agent.end fire in the
 * same long-lived plugin process for a given turn, so this is reliable; a
 * plugin restart mid-turn (very rare) just skips that one fallback.
 */
const THREAD_STATE = `${homedir()}/indeed/library/logs/thread-last-activity.json`
const GAP_THRESHOLD_MS = 30 * 60 * 1000 // idle gap that makes a thread "cold"; also the prune cutoff
const LOG_TRANSITION_BIN = `${homedir()}/bin/log-transition`
// Marker on the synthesized follow-up turn so we (a) recognize the focused turn
// and (b) never issue a second continue from it (loop guard, per Amp docs).
const LOG_REQUEST_MARKER = '[transition-log-request]'

type ThreadState = Record<string, string> // threadId -> last-activity ISO timestamp

function readThreadState(): ThreadState {
  try {
    return JSON.parse(readFileSync(THREAD_STATE, 'utf8')) as ThreadState
  } catch {
    return {}
  }
}

function writeThreadState(state: ThreadState): void {
  try {
    // Prune stale entries so the file doesn't grow without bound.
    const cutoff = Date.now() - GAP_THRESHOLD_MS
    for (const [id, ts] of Object.entries(state)) {
      const t = Date.parse(ts)
      if (!Number.isNaN(t) && t < cutoff) delete state[id]
    }
    mkdirSync(dirname(THREAD_STATE), { recursive: true })
    const tmp = `${THREAD_STATE}.tmp.${process.pid}`
    writeFileSync(tmp, JSON.stringify(state))
    renameSync(tmp, THREAD_STATE) // atomic-ish: avoid torn reads from concurrent CLIs
  } catch {
    // Never let state tracking break a turn.
  }
}

/**
 * Did the model run `log-transition` during this turn? Scans the turn's tool
 * calls for a Bash/shell command that invokes log-transition, using the
 * amp.helpers surface so we don't have to track tool.call events ourselves.
 * Conservative: any error → treat as "ran" so we never write a duplicate.
 */
function ranLogTransition(amp: PluginAPI, messages: unknown): boolean {
  try {
    const helpers = (amp as unknown as { helpers?: any }).helpers
    if (!helpers?.toolCallsInMessages || !helpers?.shellCommandFromToolCall) {
      return true // can't tell → don't risk a duplicate note
    }
    const calls = helpers.toolCallsInMessages(messages) ?? []
    for (const c of calls) {
      const sc = helpers.shellCommandFromToolCall(c.call)
      if (sc?.command && sc.command.includes('log-transition')) return true
    }
    return false
  } catch {
    return true
  }
}

/**
 * Deterministic fallback note (Layer 2). Shells out to the real log-transition
 * script (absolute path, AGENT_THREAD_ID injected so it appends the thread
 * link) so formatting + note-creation stay in one place. Tagged `[auto]` and
 * seeded from the user's prompt so the note is still meaningful.
 */
function writeFallbackTransition(threadId: string, userMessage: string): void {
  try {
    const oneLine = (userMessage ?? '').replace(/\s+/g, ' ').trim().slice(0, 140)
    const text = `[auto] ${oneLine || '(re-engaged; see thread for context)'}`
    execFileSync(LOG_TRANSITION_BIN, [text], {
      env: { ...process.env, AGENT_THREAD_ID: threadId },
      stdio: 'ignore',
    })
  } catch {
    // Never let fallback logging break a turn.
  }
}

async function appendEntry(path: string, entry: Record<string, unknown>): Promise<void> {
  try {
    await mkdir(dirname(path), { recursive: true })
    await appendFile(path, JSON.stringify(entry) + '\n', 'utf8')
  } catch {
    // Never let logging break a turn.
  }
}

/**
 * Set a WezTerm-readable user variable to signal whether Amp is waiting for
 * the user (idle, post-agent.end) or working (post-agent.start). WezTerm's
 * format-tab-title callback can read this via `pane.user_vars.ampStatus`
 * and render a ⏳ indicator on non-focused tabs.
 *
 * Uses the iTerm2 OSC 1337 SetUserVar escape (supported by WezTerm) so this
 * doesn't conflict with Amp's own OSC 0 title sets.
 */
const STATUS_DEBUG_LOG = `${homedir()}/indeed/library/logs/amp-status-debug.log`

let cachedTtyPath: string | null | undefined  // undefined = not yet probed

function findTtyPath(): string | null {
  if (cachedTtyPath !== undefined) return cachedTtyPath
  // Walk up the process tree until we find an ancestor with a real TTY.
  // Plugin processes typically don't have a controlling tty themselves
  // (ENXIO on /dev/tty), but Amp's main process and its terminal ancestor do.
  let pid: number = process.pid
  for (let i = 0; i < 15; i++) {
    try {
      const tty = execSync(`ps -p ${pid} -o tty=`, { encoding: 'utf8' }).trim()
      if (tty && tty !== '?' && tty !== '??' && !tty.startsWith('?')) {
        cachedTtyPath = `/dev/${tty}`
        return cachedTtyPath
      }
      const ppid = execSync(`ps -p ${pid} -o ppid=`, { encoding: 'utf8' }).trim()
      const next = parseInt(ppid, 10)
      if (!next || next <= 1 || next === pid) break
      pid = next
    } catch {
      break
    }
  }
  cachedTtyPath = null
  return null
}

function setAmpStatus(state: 'working' | 'waiting'): void {
  const ts = new Date().toISOString()
  const encoded = Buffer.from(state).toString('base64')
  const seq = `\x1b]1337;SetUserVar=ampStatus=${encoded}\x07`
  let result = 'ok'
  let bytes = 0
  let path = '(none)'
  try {
    const ttyPath = findTtyPath()
    if (!ttyPath) {
      result = 'no tty found in process tree'
    } else {
      path = ttyPath
      const fd = openSync(ttyPath, 'w')
      try {
        bytes = writeSync(fd, seq)
      } finally {
        closeSync(fd)
      }
    }
  } catch (err) {
    result = `error: ${err instanceof Error ? err.message : String(err)}`
  }
  try {
    void appendEntry(STATUS_DEBUG_LOG, { ts, state, result, bytes, path, pid: process.pid })
  } catch {}
}

export default function (amp: PluginAPI) {
  amp.logger.log('inject-timestamp: plugin registered')

  // In-memory record of cold turns awaiting an agent.end fallback check.
  // threadId -> the user prompt that started the cold turn.
  const coldTurns = new Map<string, string>()

  // Threads for which we issued a focused log-transition follow-up turn and are
  // awaiting its result. threadId -> original user prompt (for the [auto]
  // backstop if even the focused turn doesn't run log-transition).
  const pendingBackstop = new Map<string, string>()

  amp.on('agent.start', async (event) => {
    const now = new Date()
    setAmpStatus('working')
    void appendEntry(TURN_LOG, {
      event: 'agent.start',
      ts: now.toISOString(),
      thread_id: event.thread.id,
      message_id: event.id,
    })

    // Just-in-time transition-log reminder (Layer 1 — the model writes the
    // actual note). Fires when this thread is "cold": absent from state, or
    // idle >= threshold. If the model ignores it, agent.end writes a fallback.
    let reminder = ''
    try {
      const state = readThreadState()
      const last = state[event.thread.id]
      const cold = !last || now.getTime() - new Date(last).getTime() >= GAP_THRESHOLD_MS
      if (cold) {
        coldTurns.set(event.thread.id, event.message)
        reminder =
          '\n\n<transition-reminder>FIRST ACTION — before reading files, loading skills, ' +
          'or anything else this turn, run exactly this command once:\n' +
          '`~/bin/log-transition "a description of what we\'re working on"`\n' +
          "It appends to today's note and creates the note if missing. " +
          'Do NOT search for it (no which/type/ls/alias), do NOT ask permission, do NOT create the ' +
          'note yourself — just run it, then proceed with the task.</transition-reminder>'
      }
      state[event.thread.id] = now.toISOString()
      writeThreadState(state)
    } catch {
      // Never let transition tracking break a turn.
    }

    const display = now.toLocaleString('en-US', {
      weekday: 'long',
      year: 'numeric',
      month: 'long',
      day: 'numeric',
      hour: 'numeric',
      minute: '2-digit',
      timeZoneName: 'short',
    })
    return {
      message: {
        content: `\n\n<current-time>${display}</current-time>${reminder}`,
        display: true,
      },
    }
  })

  amp.on('agent.end', async (event) => {
    setAmpStatus('waiting')
    void appendEntry(TURN_LOG, {
      event: 'agent.end',
      ts: new Date().toISOString(),
      thread_id: event.thread.id,
      message_id: event.id,
      status: event.status,
    })

    // Mark this thread's last activity at turn end, so the next turn's gap is
    // measured from when work actually stopped (the true idle window). Done
    // BEFORE any early return so the (immediate) follow-up turn isn't "cold".
    try {
      const state = readThreadState()
      state[event.thread.id] = new Date().toISOString()
      writeThreadState(state)
    } catch {
      // ignore
    }

    // Step 3 (backstop): this IS the focused follow-up turn we injected. If the
    // model still didn't run log-transition, write the deterministic [auto]
    // note now and stop — never issue another continue (loop guard).
    if (event.message.includes(LOG_REQUEST_MARKER)) {
      const original = pendingBackstop.get(event.thread.id) ?? ''
      pendingBackstop.delete(event.thread.id)
      coldTurns.delete(event.thread.id)
      try {
        if (!ranLogTransition(amp, event.messages)) {
          writeFallbackTransition(event.thread.id, original)
        }
      } catch {
        // Never let backstop logic break a turn.
      }
      return
    }

    // Step 2: this turn was cold and the model ignored the Layer 1 reminder.
    // Give it ONE distraction-free follow-up turn whose only ask is to run
    // log-transition. (Quality note, model-written, but no competing task.)
    const coldUserMessage = coldTurns.get(event.thread.id)
    if (coldUserMessage !== undefined) {
      coldTurns.delete(event.thread.id)
      try {
        if (event.status === 'done' && !ranLogTransition(amp, event.messages)) {
          pendingBackstop.set(event.thread.id, coldUserMessage)
          return {
            action: 'continue' as const,
            userMessage:
              `${LOG_REQUEST_MARKER} Run this one command now and do nothing else: ` +
              `~/bin/log-transition "a short description of what we worked on this turn". ` +
              `Do not search for it, do not ask — just run it. Then stop.`,
          }
        }
      } catch {
        // Never let follow-up logic break a turn.
      }
    }
  })

  amp.on('tool.call', async (event) => {
    // Cast to access optional fields — the API surface may vary slightly
    // across versions and we don't want to fail loudly if the shape shifts.
    const ev = event as unknown as {
      thread?: { id?: string }
      tool?: string
      toolUseID?: string
    }
    void appendEntry(TOOL_LOG, {
      event: 'tool.call',
      ts: new Date().toISOString(),
      thread_id: ev.thread?.id,
      tool: ev.tool,
      tool_use_id: ev.toolUseID,
    })
    return { action: 'allow' as const }
  })

  amp.on('tool.result', async (event) => {
    const ev = event as unknown as {
      thread?: { id?: string }
      tool?: string
      toolUseID?: string
      status?: string
    }
    void appendEntry(TOOL_LOG, {
      event: 'tool.result',
      ts: new Date().toISOString(),
      thread_id: ev.thread?.id,
      tool: ev.tool,
      tool_use_id: ev.toolUseID,
      status: ev.status,
    })
  })
}
