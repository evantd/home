# llama-server port configuration (fish)
#
# Keep in sync with ~/.zshenv.d/llama-server.zsh (zsh equivalent).
# Centralized here so launch scripts, pipeline scripts, and OpenCode all
# read the same values. Update here, restart the servers, and start a new
# shell to pick up the new values.
#
# Topology (see BlueBarb doc § "Local model server topology, May 2026"):
#   :18080 dedicated server     (Qwen3.6-27B, always-loaded)
#   :18081 embeddings           (standalone llama-server)
#   :18082 llama-server router  (chat models, ~/Models/models-personal.ini)
#   :18083 proxycache           (KV cache proxy for dedicated server)

set -gx LLAMA_EMBED_PORT     18081
set -gx LLAMA_DEDICATED_PORT 18080
set -gx LLAMA_INFERENCE_PORT 18082
set -gx LLAMA_PROXYCACHE_PORT 18083
set -gx LLAMA_HOST           127.0.0.1

set -gx LLAMA_EMBED_URL     "http://$LLAMA_HOST:$LLAMA_EMBED_PORT"
set -gx LLAMA_DEDICATED_URL "http://$LLAMA_HOST:$LLAMA_DEDICATED_PORT"
set -gx LLAMA_INFERENCE_URL "http://$LLAMA_HOST:$LLAMA_INFERENCE_PORT"
set -gx LLAMA_PROXYCACHE_URL "http://$LLAMA_HOST:$LLAMA_PROXYCACHE_PORT"

# NOTE: This file is for the personal laptop (evans-macbook-pro.local), which
# IS the "machine with more headroom" that historically received mining
# offload from the work laptop. Mining now runs locally on each machine, so
# MINING_INFERENCE_URL is no longer set on either side.
