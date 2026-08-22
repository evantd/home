#!/bin/bash
# llama-server management script (work laptop variant)
# Usage: llama-server-work.sh {start|stop|restart|status|log|embed-log}
#
# Manages two servers (see BlueBarb doc § "Local model server topology"):
#   - Embeddings   (LLAMA_EMBED_PORT,     default 18081): embeddinggemma-300m
#   - Inference    (LLAMA_INFERENCE_PORT, default 18082): qwen3.6-moe, a DIRECT
#     single-model llama-server (no router). This box only ever serves the one
#     mining model; local OpenCode use moved off this laptop (2026-07-30), so
#     the router's model-swapping/idle-unload bought us nothing but a proxy hop
#     and a wedge failure mode. models-work.ini is now unused here.
#
# Ports come from ~/.zshenv.d/llama-server.zsh. Update there, restart, re-exec shells.
#
# Work laptop is 64 GB M3 Max. The model stays resident (no idle unload) so
# mining never pays cold-load latency, and KV is unified (--kv-unified) so a
# single large extraction prompt can use the whole ctx pool instead of a
# ctx/parallel slice. Prompts larger than ctx (262144) must be chunked by the
# mining pipeline — the model cannot serve them at all.

# Embeddings (separate process; isolated from chat models)
EMBED_MODEL="$HOME/Models/embeddinggemma-300m-GGUF/embeddinggemma-300m-qat-Q8_0.gguf"
EMBED_PORT="${LLAMA_EMBED_PORT:-18081}"
EMBED_LOG="$HOME/Models/embedding-server.log"
EMBED_PIDFILE="$HOME/Models/embedding-server.pid"

# Inference server (direct single-model; qwen3.6-moe)
INFERENCE_MODEL="$HOME/Models/Qwen3.6-35B-A3B-GGUF/Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf"
INFERENCE_MMPROJ="$HOME/Models/Qwen3.6-35B-A3B-GGUF/mmproj-F16.gguf"
INFERENCE_ALIAS="qwen3.6-moe"
PORT="${LLAMA_INFERENCE_PORT:-18082}"
HOST="${LLAMA_HOST:-127.0.0.1}"
# Total KV pool. Unified (--kv-unified) so a single request may use up to the
# full ctx; 262144 = the model's trained max (n_ctx_train). Was previously
# split ctx/parallel (262144/10 ≈ 26K/slot) which silently rejected the large
# mining prompts (observed up to 372K — those still need pipeline chunking).
INFERENCE_CTX=262144
# Server slots for mining's concurrent extraction burst. With unified KV these
# share the ctx pool rather than each getting a private ctx/parallel slice.
INFERENCE_PARALLEL=10
LOG="$HOME/Models/llama-server.log"
PIDFILE="$HOME/Models/llama-server.pid"

# Resolve the live PID of a server, verifying against the actual process rather
# than trusting the pidfile alone. Order:
#   1. pidfile PID, if alive AND its cmdline is a llama-server (guards against
#      a stale pidfile whose PID was reused by an unrelated process);
#   2. otherwise whoever is LISTENing on the port, if it's a llama-server —
#      and repair the pidfile to match (heals drift from reboots / out-of-band
#      starts / start_all_services which brings llama up but never writes pids);
#   3. otherwise not running — clear a stale pidfile.
# Echoes the PID and returns 0 when running; returns 1 when not.
resolve_pid() {
    local pidfile="$1" port="$2" pid
    if [ -f "$pidfile" ]; then
        pid=$(cat "$pidfile" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null \
           && ps -p "$pid" -o command= 2>/dev/null | grep -q llama-server; then
            echo "$pid"
            return 0
        fi
    fi
    pid=$(lsof -ti "tcp:$port" -sTCP:LISTEN 2>/dev/null | head -1)
    if [ -n "$pid" ] && ps -p "$pid" -o command= 2>/dev/null | grep -q llama-server; then
        echo "$pid" > "$pidfile"
        echo "$pid"
        return 0
    fi
    [ -f "$pidfile" ] && rm -f "$pidfile"
    return 1
}

# Poll a server's /health until it returns 200, up to $2 seconds. Returns 0 on
# ready, 1 on timeout. llama-server answers /health only once the model is
# loaded, so this catches "process alive but model still loading / crashed".
wait_health() {
    local port="$1" timeout="$2" i
    for ((i = 0; i < timeout; i++)); do
        [ "$(curl -s -o /dev/null -w '%{http_code}' "http://$HOST:$port/health" 2>/dev/null)" = "200" ] && return 0
        sleep 1
    done
    return 1
}

start_embed() {
    local pid
    if pid=$(resolve_pid "$EMBED_PIDFILE" "$EMBED_PORT"); then
        echo "embedding-server already running (PID $pid)"
        return 0
    fi
    if [ ! -f "$EMBED_MODEL" ]; then
        echo "embedding model not found: $EMBED_MODEL"
        return 1
    fi
    echo "Starting embedding-server on $HOST:$EMBED_PORT..."
    nohup llama-server \
        --model "$EMBED_MODEL" \
        --port "$EMBED_PORT" \
        --host "$HOST" \
        --embeddings \
        --ctx-size 2048 \
        --ubatch-size 2048 \
        --n-gpu-layers 99 \
        --log-verbosity 1 \
        >> "$EMBED_LOG" 2>&1 &
    echo $! > "$EMBED_PIDFILE"
    if ! kill -0 "$(cat "$EMBED_PIDFILE")" 2>/dev/null; then
        echo "embedding-server failed to spawn. Check $EMBED_LOG"
        rm -f "$EMBED_PIDFILE"
        return 1
    fi
    if wait_health "$EMBED_PORT" 30; then
        echo "embedding-server started (PID $(cat "$EMBED_PIDFILE"))"
    else
        echo "embedding-server spawned (PID $(cat "$EMBED_PIDFILE")) but /health not ready after 30s. Check $EMBED_LOG"
        tail -n 5 "$EMBED_LOG"
        return 1
    fi
}

start_inference() {
    local pid
    if pid=$(resolve_pid "$PIDFILE" "$PORT"); then
        echo "inference-server already running (PID $pid)"
        return 0
    fi
    if [ ! -f "$INFERENCE_MODEL" ]; then
        echo "inference model not found: $INFERENCE_MODEL"
        return 1
    fi
    echo "Starting inference-server on $HOST:$PORT ($INFERENCE_ALIAS, ctx=$INFERENCE_CTX, parallel=$INFERENCE_PARALLEL, unified KV)..."
    nohup llama-server \
        --model "$INFERENCE_MODEL" \
        --mmproj "$INFERENCE_MMPROJ" \
        --alias "$INFERENCE_ALIAS" \
        --port "$PORT" \
        --host "$HOST" \
        --n-gpu-layers 99 \
        --cache-type-k q8_0 \
        --cache-type-v q8_0 \
        --jinja \
        --ctx-size "$INFERENCE_CTX" \
        --kv-unified \
        --parallel "$INFERENCE_PARALLEL" \
        --temp 0.6 \
        --top-p 0.95 \
        --top-k 20 \
        --log-verbosity 1 \
        >> "$LOG" 2>&1 &
    echo $! > "$PIDFILE"
    if ! kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        echo "inference-server failed to spawn. Check $LOG"
        rm -f "$PIDFILE"
        return 1
    fi
    # 35B model load is slow; poll /health rather than a fixed sleep.
    if wait_health "$PORT" 180; then
        echo "inference-server started (PID $(cat "$PIDFILE"))"
    else
        echo "inference-server spawned (PID $(cat "$PIDFILE")) but /health not ready after 180s. Check $LOG"
        tail -n 5 "$LOG"
        return 1
    fi
}

start() {
    start_embed
    start_inference
}

stop_one() {
    local label="$1" pidfile="$2" port="$3" pid
    if pid=$(resolve_pid "$pidfile" "$port"); then
        echo "Stopping $label (PID $pid)..."
        kill "$pid"
        sleep 2
        kill -0 "$pid" 2>/dev/null && kill -9 "$pid"
        rm -f "$pidfile"
    fi
    echo "$label stopped"
}

stop() {
    stop_one "inference-server" "$PIDFILE" "$PORT"
    stop_one "embedding-server" "$EMBED_PIDFILE" "$EMBED_PORT"
}

status() {
    local pid
    if pid=$(resolve_pid "$EMBED_PIDFILE" "$EMBED_PORT"); then
        echo "embedding-server  running (PID $pid) :$EMBED_PORT"
    else
        echo "embedding-server  not running"
    fi
    if pid=$(resolve_pid "$PIDFILE" "$PORT"); then
        echo "inference-server running (PID $pid) :$PORT ($INFERENCE_ALIAS)"
        curl -s "http://$HOST:$PORT/v1/models" 2>/dev/null | python3 -m json.tool 2>/dev/null | head -40 || echo "  (no /v1/models response)"
    else
        echo "inference-server not running"
    fi
}

case "${1:-status}" in
    start)       start ;;
    stop)        stop ;;
    restart)     stop; sleep 1; start ;;
    status)      status ;;
    log)         tail -f "$LOG" ;;
    embed-log)   tail -f "$EMBED_LOG" ;;
    *)           echo "Usage: $0 {start|stop|restart|status|log|embed-log}" ;;
esac
