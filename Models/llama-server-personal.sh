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

# Dedicated server (always loaded, never sleeps)
# Dense model — best accuracy (82.5% on harness-bench), primary for all work
DEDICATED_MODEL="$HOME/Models/Qwen3.6-27B-GGUF/Qwen3.6-27B-UD-Q4_K_XL.gguf"
DEDICATED_PORT="${LLAMA_DEDICATED_PORT:-18080}"
DEDICATED_LOG="$HOME/Models/dedicated-server.log"
DEDICATED_PIDFILE="$HOME/Models/dedicated-server.pid"

# llama-server router mode (chat models, excluding MoE which runs standalone)
PRESET="$HOME/Models/models-personal.ini"
PORT="${LLAMA_INFERENCE_PORT:-18082}"
HOST="${LLAMA_HOST:-127.0.0.1}"
MODELS_MAX=1
SLEEP_IDLE=600
LOG_VERBOSITY=2
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
    wait_for_port_free "$EMBED_PORT" 10
    echo "Starting embedding-server on $HOST:$EMBED_PORT..."
    nohup llama-server \
        --model "$EMBED_MODEL" \
        --port "$EMBED_PORT" \
        --host "$HOST" \
        --embeddings \
        --ctx-size 2048 \
        --ubatch-size 2048 \
        --n-gpu-layers 99 \
        --log-timestamps \
        --log-verbosity "$LOG_VERBOSITY" \
        --metrics \
        2>&1 | LOG_NAME="embedding-server.log" python3 "$HOME/Models/log_wrapper.py" &
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

start_dedicated() {
    if [ -f "$DEDICATED_PIDFILE" ] && kill -0 "$(cat "$DEDICATED_PIDFILE")" 2>/dev/null; then
        echo "Dedicated server already running (PID $(cat "$DEDICATED_PIDFILE"))"
        return 0
    fi
    if [ ! -f "$DEDICATED_MODEL" ]; then
        echo "Dedicated model not found: $DEDICATED_MODEL"
        return 1
    fi
    wait_for_port_free "$DEDICATED_PORT" 15
    echo "Starting dedicated server on $HOST:$DEDICATED_PORT (always loaded, never sleeps)..."
    nohup llama-server \
        --model "$DEDICATED_MODEL" \
        --port "$DEDICATED_PORT" \
        --host "$HOST" \
        --alias qwen3.6-27b \
        --ctx-size 262144 \
        --n-gpu-layers 99 \
        --parallel 4 \
        --temp 0.6 \
        --top-p 0.95 \
        --top-k 20 \
        --cache-type-k q8_0 \
        --cache-type-v q8_0 \
        --jinja \
        --log-timestamps \
        --log-verbosity "$LOG_VERBOSITY" \
        --metrics \
        --perf \
        --kv-unified \
        --chat-template-kwargs '{"preserve_thinking":true}' \
        2>&1 | LOG_NAME="dedicated-server.log" python3 "$HOME/Models/log_wrapper.py" &
    echo $! > "$DEDICATED_PIDFILE"
    sleep 3
    if kill -0 "$(cat "$DEDICATED_PIDFILE")" 2>/dev/null; then
        echo "Dedicated server started (PID $(cat "$DEDICATED_PIDFILE"))"
    else
        echo "Dedicated server failed. Check $DEDICATED_LOG"
        rm -f "$DEDICATED_PIDFILE"
        return 1
    fi
}

start_router() {
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        echo "llama-server router already running (PID $(cat "$PIDFILE"))"
        return 0
    fi
    wait_for_port_free "$PORT" 15
    echo "Starting llama-server router on $HOST:$PORT (models-max=$MODELS_MAX, sleep-idle=${SLEEP_IDLE}s)..."
    nohup llama-server \
        --models-preset "$PRESET" \
        --port "$PORT" \
        --host "$HOST" \
        --models-max "$MODELS_MAX" \
        --sleep-idle-seconds "$SLEEP_IDLE" \
        --chat-template-kwargs '{"preserve_thinking":true}' \
        --kv-unified \
        --log-timestamps \
        --log-verbosity "$LOG_VERBOSITY" \
        --metrics \
        --perf \
        2>&1 | python3 "$HOME/Models/log_wrapper.py" &
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

# Wait for a port to become free (process exited and released the socket).
# Retries up to $1 seconds, sleeping 0.5s between checks.
# Uses lsof on macOS (ss is Linux-only).
wait_for_port_free() {
    local port="$1" max_wait="${2:-15}" elapsed=0
    while lsof -i :"$port" -sTCP:LISTEN 2>/dev/null | grep -q LISTEN; do
        if [ $elapsed -ge $max_wait ]; then
            echo "  WARNING: port $port still in use after ${max_wait}s — proceeding anyway"
            break
        fi
        sleep 0.5
        elapsed=$((elapsed + 1))
    done
}

start() {
    start_embed
    start_dedicated
    start_router
}

stop_one() {
    local label="$1" pidfile="$2" pattern="$3" port="$4"
    # Always kill by port as a fallback — the pidfile may contain the
    # wrapper PID (from pipeline $!), not the actual llama-server child.
    if [ -n "$port" ]; then
        local pids
        pids=$(lsof -t -i :"$port" -sTCP:LISTEN 2>/dev/null)
        if [ -n "$pids" ]; then
            echo "Stopping $label (ports:$port, PIDs:$pids)..."
            # Graceful shutdown first
            kill $pids 2>/dev/null
            sleep 3
            # Force kill anything still holding the port
            pids=$(lsof -t -i :"$port" -sTCP:LISTEN 2>/dev/null)
            [ -n "$pids" ] && kill -9 $pids 2>/dev/null
            sleep 1
        fi
    fi
    # Also clean up the pidfile if it still exists
    if [ -f "$pidfile" ]; then
        rm -f "$pidfile"
    fi
    echo "$label stopped"
}

stop() {
    stop_one "Dedicated server" "$DEDICATED_PIDFILE" "" "$DEDICATED_PORT"
    stop_one "llama-server router" "$PIDFILE" "" "$PORT"
    stop_one "embedding-server" "$EMBED_PIDFILE" "" "$EMBED_PORT"
}

status() {
    if [ -f "$EMBED_PIDFILE" ] && kill -0 "$(cat "$EMBED_PIDFILE")" 2>/dev/null; then
        echo "embedding-server  running (PID $(cat "$EMBED_PIDFILE")) :$EMBED_PORT"
    else
        echo "embedding-server  not running"
    fi
    if [ -f "$DEDICATED_PIDFILE" ] && kill -0 "$(cat "$DEDICATED_PIDFILE")" 2>/dev/null; then
        echo "Dedicated server  running (PID $(cat "$DEDICATED_PIDFILE")) :$DEDICATED_PORT"
        if curl -s "http://$HOST:$DEDICATED_PORT/metrics" 2>/dev/null | grep -q "llama"; then
            echo "  metrics endpoint: available"
        else
            echo "  metrics endpoint: not responding"
        fi
    else
        echo "Dedicated server  not running"
    fi
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        echo "llama-server router running (PID $(cat "$PIDFILE")) :$PORT"
        if curl -s "http://$HOST:$PORT/metrics?model=qwen3.6-27b" >/dev/null 2>&1; then
            echo "  metrics endpoint: available"
        else
            echo "  metrics endpoint: not responding (may need --metrics flag)"
        fi
    else
        echo "llama-server router not running"
    fi
}

case "${1:-status}" in
    start)       start ;;
    stop)        stop ;;
    restart)     stop; sleep 5; start ;;
    status)      status ;;
    log)         tail -f "$LOG" ;;
    embed-log)   tail -f "$EMBED_LOG" ;;
    dedicated-log) tail -f "$DEDICATED_LOG" ;;
    *)           echo "Usage: $0 {start|stop|restart|status|log|embed-log|dedicated-log}" ;;
esac
