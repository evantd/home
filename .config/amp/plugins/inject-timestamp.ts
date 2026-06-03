import type { PluginAPI } from '@ampcode/plugin'
import { appendFile, mkdir } from 'node:fs/promises'
import { closeSync, openSync, writeSync } from 'node:fs'
import { execSync } from 'node:child_process'
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

  amp.on('agent.start', async (event) => {
    const now = new Date()
    setAmpStatus('working')
    void appendEntry(TURN_LOG, {
      event: 'agent.start',
      ts: now.toISOString(),
      thread_id: event.thread.id,
      message_id: event.id,
    })

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
        content: `\n\n<current-time>${display}</current-time>`,
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
