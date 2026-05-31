# llama-server port configuration (zsh)
#
# Keep in sync with ~/.config/fish/conf.d/llama-server.fish (fish equivalent).
# Both ports moved off the 8080/8081 range due to too much competition.
# Centralized here so launch scripts, pipeline scripts, and OpenCode all
# read the same values. Update here, restart the servers, and re-exec
# any open shells that need to pick up the new values.

export LLAMA_INFERENCE_PORT=18080
export LLAMA_EMBED_PORT=18081
export LLAMA_HOST=127.0.0.1

export LLAMA_INFERENCE_URL="http://${LLAMA_HOST}:${LLAMA_INFERENCE_PORT}"
export LLAMA_EMBED_URL="http://${LLAMA_HOST}:${LLAMA_EMBED_PORT}"

# Mining (phase 1) + corpus dedupe (phase 5) offload to the personal laptop
# (evans-macbook-pro.local) which has more headroom than this work machine.
# Falls back to LLAMA_INFERENCE_URL if unset (see
# scripts/llama_server_config.py: MINING_INFERENCE_URL).
# Classification (phase 10) keeps using LLAMA_INFERENCE_URL above so it
# coexists with interactive OpenCode use on this box.
#
# The personal laptop deliberately does NOT set this (it IS the target) — see
# ~/.config/fish/conf.d/llama-server.fish.
export MINING_INFERENCE_URL="http://evans-macbook-pro.local:${LLAMA_INFERENCE_PORT}"
