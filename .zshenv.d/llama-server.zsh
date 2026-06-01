# llama-server port configuration (zsh)
#
# Keep in sync with ~/.config/fish/conf.d/llama-server.fish (fish equivalent
# on personal laptop). Centralized here so launch scripts, pipeline scripts,
# and OpenCode all read the same values. Update here, restart the servers,
# and re-exec any open shells that need to pick up the new values.
#
# Topology (see BlueBarb doc § "Local model server topology, May 2026"):
#   :18081 embeddings           (standalone llama-server)
#   :18082 llama-server router  (chat models, ~/Models/models-work.ini)
#
# OptiLLM (was :18083) is currently NOT in the default path because its
# router_plugin reloads ModernBERT per request (~10s tax). Re-enable when
# fixed upstream or patched locally.

export LLAMA_EMBED_PORT=18081
export LLAMA_INFERENCE_PORT=18082
export LLAMA_HOST=127.0.0.1

export LLAMA_EMBED_URL="http://${LLAMA_HOST}:${LLAMA_EMBED_PORT}"
export LLAMA_INFERENCE_URL="http://${LLAMA_HOST}:${LLAMA_INFERENCE_PORT}"

# MINING_INFERENCE_URL deliberately NOT set: mining pipeline (Phase 1+5+10)
# now runs fully locally on whichever machine you're on, sharing the local
# router with OpenCode. The scripts/llama_server_config.py fallback to
# LLAMA_INFERENCE_URL is exactly what we want.
