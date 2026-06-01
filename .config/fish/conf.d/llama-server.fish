# llama-server port configuration (fish)
#
# Keep in sync with ~/.zshenv.d/llama-server.zsh (zsh equivalent).
# Centralized here so launch scripts, pipeline scripts, and OpenCode all
# read the same values. Update here, restart the servers, and start a new
# shell to pick up the new values.
#
# Topology (see BlueBarb doc § "Local model server topology, May 2026"):
#   :18081 embeddings           (standalone llama-server)
#   :18082 llama-server router  (chat models, ~/Models/models.ini)
#   :18083 OptiLLM              (approach=router; upstream → router :18082)
#
# OpenCode default → OptiLLM (:18083) so it gets approach-routing.
# Direct bypass for safety/debugging → router (:18082).

set -gx LLAMA_EMBED_PORT     18081
set -gx LLAMA_INFERENCE_PORT 18082
set -gx OPTILLM_PORT         18083
set -gx LLAMA_HOST           127.0.0.1

set -gx LLAMA_EMBED_URL     "http://$LLAMA_HOST:$LLAMA_EMBED_PORT"
set -gx LLAMA_INFERENCE_URL "http://$LLAMA_HOST:$LLAMA_INFERENCE_PORT"
set -gx OPTILLM_URL         "http://$LLAMA_HOST:$OPTILLM_PORT"

# NOTE: This file is for the personal laptop (evans-macbook-pro.local), which
# IS the "machine with more headroom" that the work laptop offloads mining to.
# So we deliberately do NOT set MINING_INFERENCE_URL here — the mining pipeline
# falls back to LLAMA_INFERENCE_URL (local) when unset, which is correct.
#
# See ~/.zshenv.d/llama-server.zsh for the work-laptop side that points at
# this machine.
