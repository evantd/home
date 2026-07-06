#!/bin/bash
# llama-server management script (personal laptop variant)
# Usage: llama-server-personal.sh {start|stop|restart|restart-dedicated|restart-router|status|log|embed-log|dedicated-log}
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
#
# KV cache math — sliding window layers DO get cached (window limits attention,
# not storage). All attention layers count, not just global.
#
# Qwen3.6-27B (dense, per https://huggingface.co/unsloth/Qwen3.6-27B-MTP-GGUF):
#   - 64 layers: 16×(3× DeltaNet + 1× Gated Attention); only 16 attn layers
#   - Gated Attention: 4 KV heads × 256 head dim
#   - KV/token: 16 × 4 × 256 × 2 = 32,768 values (32 KiB @ q8, 64 KiB @ f16)
#
# Qwen3.6-35B-A3B (MoE, per https://huggingface.co/Qwen/Qwen3.6-35B-A3B):
#   - 40 layers: 10×(3× DeltaNet + 1× Gated Attention); only 10 attn layers
#   - Gated Attention: 2 KV heads × 256 head dim
#   - KV/token: 10 × 2 × 256 × 2 = 10,240 values (10 KiB @ q8, 20 KiB @ f16)
#
# Gemma-4-26B-A4B (MoE, per https://huggingface.co/google/gemma-4-26B-A4B):
#   - 30 layers: 25 sliding (4 KV × 256) + 5 global (4 KV × 512)
#   - Both layer types = 1,024 values each
#   - KV/token: 30 × 1,024 × 2 = 61,440 values (60 KiB @ q8, 120 KiB @ f16)
#
# Gemma-4-31B-IT (dense, per https://huggingface.co/blog/lujangusface/tw-eagle3-gemma4):
#   - 60 layers: 50 sliding (8 KV × 256) + 10 global (4 KV × 512)
#   - Both layer types = 2,048 values each
#   - KV/token: 60 × 2,048 × 2 = 245,760 values (240 KiB @ q8, 480 KiB @ f16)
#
# KV cache size by context (q8_0):
#   Model           | 128K    | 262K    | 524K
#   Qwen3.6-27B     | ~4.0 GB | ~8.0 GB | ~16.0 GB
#   Qwen3.6-35B-A3B | ~1.2 GB | ~2.4 GB | ~4.9 GB
#   Gemma-4-26B-A4B | ~7.6 GB | ~15.3 GB| ~30.5 GB
#   Gemma-4-31B-IT  | ~30.0 GB| ~60.0 GB| ~120.0 GB
#
# Total GPU memory ≈ model weights + KV cache (q8_0):
#   Qwen3.6-27B @ 262K: ~30 GB  |  Gemma-4-26B-A4B @ 262K: ~32 GB
#   Qwen3.6-35B-A3B @ 262K: ~20 GB | Gemma-4-31B-IT @ 262K: ~95 GB
#
# --ctx-size (num-ctx) is the TOTAL context pool shared across all slots.
# With --kv-unified, llama.cpp allocates a single contiguous block of num-ctx
# tokens; slots share prefixes and draw from the same pool.
# With --no-kv-unified, each of `parallel` slots gets its own num-ctx/parallel
# allocation — easier to allocate but no prefix sharing.
#
# Individual slot context is still capped at the training max (262,144). Setting
# num-ctx higher than that is fine for supporting multiple slots that collectively
# need more context, but llama.cpp will warn and cap per-slot to 262K.
#
# On 128GB Apple Silicon, 524K @ q8 (~38 GB GPU) fits. Metal command buffer
# working memory can still OOM during large decode batches — Metal has its own
# limits beyond the KV cache.
DEDICATED_MODEL="$HOME/Models/Qwen3.6-27B-MTP-GGUF/Qwen3.6-27B-Q8_0.gguf"
DEDICATED_PORT="${LLAMA_DEDICATED_PORT:-18080}"
DEDICATED_LOG="$HOME/Models/dedicated-server.log"
DEDICATED_PIDFILE="$HOME/Models/dedicated-server.pid"

# llama-server router mode (chat models, excluding MoE which runs standalone)
PRESET="$HOME/Models/models-personal.ini"
PORT="${LLAMA_INFERENCE_PORT:-18082}"
HOST="${LLAMA_HOST:-127.0.0.1}"
MODELS_MAX=1
SLEEP_IDLE=600
LOG_VERBOSITY=3
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
    nohup bash -c "stdbuf -oL -eL llama-server \
        --model \"$EMBED_MODEL\" \
        --port \"$EMBED_PORT\" \
        --host \"$HOST\" \
        --embeddings \
        --ctx-size 2048 \
        --ubatch-size 2048 \
        --n-gpu-layers 99 \
        --log-timestamps \
        --log-verbosity \"$LOG_VERBOSITY\" \
        --metrics \
        2>&1 | LOG_NAME=\"embedding-server.log\" python3 \"$HOME/Models/log_wrapper.py\"" >/dev/null 2>/dev/null &
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
    nohup bash -c "stdbuf -oL -eL llama-server \
        --model \"$DEDICATED_MODEL\" \
        --port \"$DEDICATED_PORT\" \
        --host \"$HOST\" \
        --alias qwen3.6-27b \
        --ctx-size 262144 \
        --n-gpu-layers 99 \
        --parallel 2 \
        --temp 0.6 \
        --top-p 0.95 \
        --top-k 20 \
        --cache-type-k q8_0 \
        --cache-type-v q8_0 \
        --jinja \
        --log-timestamps \
        --log-verbosity \"$LOG_VERBOSITY\" \
        --metrics \
        --perf \
        --kv-unified \
        --slot-save-path \"$HOME/Models/slot-cache\" \
        --spec-type draft-mtp \
        --spec-draft-n-max 4 \
        --chat-template-kwargs '{\"preserve_thinking\":false}' \
        2>&1 | LOG_NAME=\"dedicated-server.log\" python3 \"$HOME/Models/log_wrapper.py\"" >/dev/null 2>/dev/null &
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
    nohup bash -c "stdbuf -oL -eL llama-server \
        --models-preset \"$PRESET\" \
        --port \"$PORT\" \
        --host \"$HOST\" \
        --models-max $MODELS_MAX \
        --sleep-idle-seconds $SLEEP_IDLE \
        --chat-template-kwargs '{\"preserve_thinking\":false}' \
        --kv-unified \
        --log-timestamps \
        --log-verbosity $LOG_VERBOSITY \
        --metrics \
        --perf \
        2>&1 | python3 \"$HOME/Models/log_wrapper.py\"" >/dev/null 2>/dev/null &
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

restart_dedicated() {
    stop_one "Dedicated server" "$DEDICATED_PIDFILE" "" "$DEDICATED_PORT"
    sleep 3
    start_dedicated
}

restart_router() {
    stop_one "llama-server router" "$PIDFILE" "" "$PORT"
    sleep 3
    start_router
}

case "${1:-status}" in
    start)       start ;;
    stop)        stop ;;
    restart)     stop; sleep 5; start ;;
    restart-dedicated) restart_dedicated ;;
    restart-router)    restart_router ;;
    status)      status ;;
    log)         tail -f "$DEDICATED_LOG" ;;
    embed-log)   tail -f "$EMBED_LOG" ;;
    dedicated-log) tail -f "$DEDICATED_LOG" ;;
    *)           echo "Usage: $0 {start|stop|restart|restart-dedicated|restart-router|status|log|embed-log|dedicated-log}" ;;
esac
