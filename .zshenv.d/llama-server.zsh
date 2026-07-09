# llama-server port configuration (zsh)
#
# Keep in sync with ~/.config/fish/conf.d/llama-server.fish (fish equivalent
# on personal laptop). Centralized here so launch scripts, pipeline scripts,
# and OpenCode all read the same values. Update here, restart the servers,
# and re-exec any open shells that need to pick up the new values.
#
# Topology (see BlueBarb doc § "Local model server topology, May 2026"):
#   :18080 dedicated server     (Qwen3.6-27B, always-loaded)
#   :18081 embeddings           (standalone llama-server)
#   :18082 llama-server router  (chat models, ~/Models/models-work.ini)
#   :18083 proxycache           (KV cache proxy for dedicated server)

export LLAMA_EMBED_PORT=18081
export LLAMA_DEDICATED_PORT=18080
export LLAMA_INFERENCE_PORT=18082
export LLAMA_PROXYCACHE_PORT=18083
export LLAMA_HOST=127.0.0.1

export LLAMA_EMBED_URL="http://${LLAMA_HOST}:${LLAMA_EMBED_PORT}"
export LLAMA_DEDICATED_URL="http://${LLAMA_HOST}:${LLAMA_DEDICATED_PORT}"
export LLAMA_INFERENCE_URL="http://${LLAMA_HOST}:${LLAMA_INFERENCE_PORT}"
export LLAMA_PROXYCACHE_URL="http://${LLAMA_HOST}:${LLAMA_PROXYCACHE_PORT}"

# MINING_INFERENCE_URL points at the dedicated server so mining (phase 1+5)
# uses the always-warm dense model instead of loading on-demand via router.
export MINING_INFERENCE_URL="http://${LLAMA_HOST}:${LLAMA_DEDICATED_PORT}"
