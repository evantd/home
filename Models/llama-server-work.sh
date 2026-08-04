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

start_embed() {
    if [ -f "$EMBED_PIDFILE" ] && kill -0 "$(cat "$EMBED_PIDFILE")" 2>/dev/null; then
        echo "embedding-server already running (PID $(cat "$EMBED_PIDFILE"))"
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
    sleep 2
    if kill -0 "$(cat "$EMBED_PIDFILE")" 2>/dev/null; then
        echo "embedding-server started (PID $(cat "$EMBED_PIDFILE"))"
    else
        echo "embedding-server failed. Check $EMBED_LOG"
        rm -f "$EMBED_PIDFILE"
        return 1
    fi
}

start_inference() {
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        echo "inference-server already running (PID $(cat "$PIDFILE"))"
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
    sleep 3
    if kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        echo "inference-server started (PID $(cat "$PIDFILE"))"
    else
        echo "inference-server failed. Check $LOG"
        rm -f "$PIDFILE"
        return 1
    fi
}

start() {
    start_embed
    start_inference
}

stop_one() {
    local label="$1" pidfile="$2" pattern="$3"
    if [ -f "$pidfile" ]; then
        local pid
        pid=$(cat "$pidfile")
        if kill -0 "$pid" 2>/dev/null; then
            echo "Stopping $label (PID $pid)..."
            kill "$pid"
            sleep 2
            kill -0 "$pid" 2>/dev/null && kill -9 "$pid"
        fi
        rm -f "$pidfile"
    elif [ -n "$pattern" ]; then
        pkill -f "$pattern" 2>/dev/null
    fi
    echo "$label stopped"
}

stop() {
    stop_one "inference-server" "$PIDFILE" "llama-server.*--alias $INFERENCE_ALIAS"
    stop_one "embedding-server" "$EMBED_PIDFILE" "llama-server.*--embeddings.*--port $EMBED_PORT"
}

status() {
    if [ -f "$EMBED_PIDFILE" ] && kill -0 "$(cat "$EMBED_PIDFILE")" 2>/dev/null; then
        echo "embedding-server  running (PID $(cat "$EMBED_PIDFILE")) :$EMBED_PORT"
    else
        echo "embedding-server  not running"
    fi
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        echo "inference-server running (PID $(cat "$PIDFILE")) :$PORT ($INFERENCE_ALIAS)"
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
