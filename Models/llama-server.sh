#!/bin/bash
# llama-server management script
# Usage: llama-server.sh {start|stop|restart|status|log|embed-log|optillm-log}
#
# Manages three servers (see BlueBarb doc § "Local model server topology"):
#   - Embeddings           (LLAMA_EMBED_PORT,     default 18081): embeddinggemma-300m
#   - llama-server router  (LLAMA_INFERENCE_PORT, default 18082): all chat models (qwen/gemma)
#   - OptiLLM              (OPTILLM_PORT,         default 18083): approach=router; upstream → router :18082
#
# Ports come from ~/.config/fish/conf.d/llama-server.fish (fish) /
# ~/.zshenv.d/llama-server.zsh (zsh). Update them there, restart, re-exec shells.
#
# OpenCode default: :18083 (OptiLLM). Bypass for safety/recovery: :18082 (router).

# Embeddings (separate process; isolated from chat models)
EMBED_MODEL="$HOME/Models/embeddinggemma-300m-GGUF/embeddinggemma-300m-qat-Q8_0.gguf"
EMBED_PORT="${LLAMA_EMBED_PORT:-18081}"
EMBED_LOG="$HOME/Models/embedding-server.log"
EMBED_PIDFILE="$HOME/Models/embedding-server.pid"

# llama-server router mode (chat models)
PRESET="$HOME/Models/models.ini"
PORT="${LLAMA_INFERENCE_PORT:-18082}"
HOST="${LLAMA_HOST:-127.0.0.1}"
MODELS_MAX=2
SLEEP_IDLE=60
LOG="$HOME/Models/llama-server.log"
PIDFILE="$HOME/Models/llama-server.pid"

# OptiLLM (approach=router)
OPTILLM_PORT_VAL="${OPTILLM_PORT:-18083}"
OPTILLM_HOST="${OPTILLM_HOST:-127.0.0.1}"
OPTILLM_LOG="$HOME/Models/optillm.log"
OPTILLM_PIDFILE="$HOME/Models/optillm.pid"
OPTILLM_BIN="${OPTILLM_BIN:-$HOME/.local/bin/optillm}"

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

start_optillm() {
    if [ -f "$OPTILLM_PIDFILE" ] && kill -0 "$(cat "$OPTILLM_PIDFILE")" 2>/dev/null; then
        echo "optillm already running (PID $(cat "$OPTILLM_PIDFILE"))"
        return 0
    fi
    if [ ! -x "$OPTILLM_BIN" ]; then
        # try pipx shim and venv bin
        if [ -x "$HOME/.local/pipx/venvs/optillm/bin/optillm" ]; then
            OPTILLM_BIN="$HOME/.local/pipx/venvs/optillm/bin/optillm"
        elif [ -x "$HOME/.local/optillm-venv/bin/optillm" ]; then
            OPTILLM_BIN="$HOME/.local/optillm-venv/bin/optillm"
        else
            echo "optillm binary not found (tried $OPTILLM_BIN and common venvs)"
            return 1
        fi
    fi
    echo "Starting OptiLLM on $OPTILLM_HOST:$OPTILLM_PORT_VAL (approach=router → router :$PORT)..."
    # OPENAI_API_KEY=dummy because llama-server doesn't check it but the
    # openai client refuses to start without one. --base-url overrides the
    # YAML's backend.openai_api_base.
    OPENAI_API_KEY=dummy nohup "$OPTILLM_BIN" \
        --port "$OPTILLM_PORT_VAL" \
        --host "$OPTILLM_HOST" \
        --approach router \
        --base-url "http://127.0.0.1:$PORT/v1" \
        >> "$OPTILLM_LOG" 2>&1 &
    echo $! > "$OPTILLM_PIDFILE"
    sleep 3
    if kill -0 "$(cat "$OPTILLM_PIDFILE")" 2>/dev/null; then
        echo "optillm started (PID $(cat "$OPTILLM_PIDFILE"))"
    else
        echo "optillm failed to start. Check $OPTILLM_LOG"
        rm -f "$OPTILLM_PIDFILE"
        return 1
    fi
}

start() {
    start_embed
    start_router
    start_optillm
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
    stop_one "optillm" "$OPTILLM_PIDFILE" "optillm.*--port $OPTILLM_PORT_VAL"
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
    if [ -f "$OPTILLM_PIDFILE" ] && kill -0 "$(cat "$OPTILLM_PIDFILE")" 2>/dev/null; then
        echo "optillm           running (PID $(cat "$OPTILLM_PIDFILE")) :$OPTILLM_PORT_VAL"
    else
        echo "optillm           not running"
    fi
}

case "${1:-status}" in
    start)       start ;;
    stop)        stop ;;
    restart)     stop; sleep 1; start ;;
    status)      status ;;
    log)         tail -f "$LOG" ;;
    embed-log)   tail -f "$EMBED_LOG" ;;
    optillm-log) tail -f "$OPTILLM_LOG" ;;
    *)           echo "Usage: $0 {start|stop|restart|status|log|embed-log|optillm-log}" ;;
esac
