# llama-server port configuration (fish)
#
# Keep in sync with ~/.zshenv.d/llama-server.zsh (zsh equivalent).
# Both ports moved off the 8080/8081 range due to too much competition.
# Centralized here so launch scripts, pipeline scripts, and OpenCode all
# read the same values. Update here, restart the servers, and start a new
# shell to pick up the new values.

set -gx LLAMA_INFERENCE_PORT 18080
set -gx LLAMA_EMBED_PORT 18081
set -gx LLAMA_HOST 127.0.0.1

set -gx LLAMA_INFERENCE_URL "http://$LLAMA_HOST:$LLAMA_INFERENCE_PORT"
set -gx LLAMA_EMBED_URL "http://$LLAMA_HOST:$LLAMA_EMBED_PORT"

# Mining (phase 1) + corpus dedupe (phase 5) target a second machine on the
# LAN with more headroom. Falls back to LLAMA_INFERENCE_URL if unset (see
# scripts/llama_server_config.py: MINING_INFERENCE_URL).
# Classification (phase 10) keeps using LLAMA_INFERENCE_URL above so it
# coexists with interactive OpenCode use on this box.
#
# Override on the personal laptop if evans-macbook-pro.local isn't reachable
# from your network.
set -gx MINING_INFERENCE_URL "http://evans-macbook-pro.local:$LLAMA_INFERENCE_PORT"
