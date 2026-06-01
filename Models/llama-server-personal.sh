#!/bin/bash
# llama-server management script (personal laptop variant)
# Usage: llama-server-personal.sh {start|stop|restart|status|log|embed-log}
#
# Manages two servers (see BlueBarb doc § "Local model server topology"):
#   - Embeddings           (LLAMA_EMBED_PORT,     default 18081): embeddinggemma-300m
#   - llama-server router  (LLAMA_INFERENCE_PORT, default 18082): chat models per models-personal.ini
#
# Ports come from ~/.config/fish/conf.d/llama-server.fish (fish) /
# ~/.zshenv.d/llama-server.zsh (zsh). Update them there, restart, re-exec shells.
#
# OptiLLM was tried May 31, 2026 but pulled from the default path: its
# `approach: router` plugin reloads the ModernBERT classifier per request
# (no module-level cache in upstream router_plugin.py), adding ~10s/request.
# Re-enable when that's fixed upstream (or by us) — start it manually with
# `optillm --port 18083 --base-url http://127.0.0.1:18082/v1 ...` and re-add
# the `optillm` provider to ~/.config/opencode/opencode.json.

# Embeddings (separate process; isolated from chat models)
EMBED_MODEL="$HOME/Models/embeddinggemma-300m-GGUF/embeddinggemma-300m-qat-Q8_0.gguf"
EMBED_PORT="${LLAMA_EMBED_PORT:-18081}"
EMBED_LOG="$HOME/Models/embedding-server.log"
EMBED_PIDFILE="$HOME/Models/embedding-server.pid"

# llama-server router mode (chat models)
PRESET="$HOME/Models/models-personal.ini"
PORT="${LLAMA_INFERENCE_PORT:-18082}"
HOST="${LLAMA_HOST:-127.0.0.1}"
MODELS_MAX=2
SLEEP_IDLE=60
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

start_router() {
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        echo "llama-server router already running (PID $(cat "$PIDFILE"))"
        return 0
    fi
    echo "Starting llama-server router on $HOST:$PORT (models-max=$MODELS_MAX, sleep-idle=${SLEEP_IDLE}s)..."
    nohup llama-server \
        --models-preset "$PRESET" \
        --port "$PORT" \
        --host "$HOST" \
        --models-max "$MODELS_MAX" \
        --sleep-idle-seconds "$SLEEP_IDLE" \
        --log-verbosity 1 \
        >> "$LOG" 2>&1 &
    echo $! > "$PIDFILE"
    sleep 3
    if kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        echo "llama-server router started (PID $(cat "$PIDFILE"))"
    else
        echo "llama-server router failed. Check $LOG"
        rm -f "$PIDFILE"
        return 1
    fi
}

start() {
    start_embed
    start_router
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
    stop_one "llama-server router" "$PIDFILE" "llama-server.*--models-preset"
    stop_one "embedding-server" "$EMBED_PIDFILE" "llama-server.*--embeddings.*--port $EMBED_PORT"
}

status() {
    if [ -f "$EMBED_PIDFILE" ] && kill -0 "$(cat "$EMBED_PIDFILE")" 2>/dev/null; then
        echo "embedding-server  running (PID $(cat "$EMBED_PIDFILE")) :$EMBED_PORT"
    else
        echo "embedding-server  not running"
    fi
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        echo "llama-server router running (PID $(cat "$PIDFILE")) :$PORT"
        curl -s "http://$HOST:$PORT/v1/models" 2>/dev/null | python3 -m json.tool 2>/dev/null | head -40 || echo "  (no /v1/models response)"
    else
        echo "llama-server router not running"
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
