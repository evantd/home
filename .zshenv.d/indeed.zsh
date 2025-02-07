export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"

# Save disk space by discarding previous versions of artifacts.
export PREVIOUS_ITEMS_TO_KEEP=0
export MAX_KEPT=1

# SourceGraph CLI setup
# https://sourcegraph.com/docs/cli/quickstart
export SRC_ENDPOINT=https://indeed.sourcegraph.com
# See sourcegraph_token.zsh for this next bit, and don't commit it.
#SRC_ACCESS_TOKEN=sgp_dontstealmytokenbro
