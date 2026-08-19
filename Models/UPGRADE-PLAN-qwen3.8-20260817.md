# Qwen3.8 + Muse Glimmer + Nemotron 3.5 Upgrade Plan

**Date:** 2026-08-17
**Hardware:** M5 Max, 128GB unified memory
**llama.cpp:** 10270
**Est. total time:** 45–75 min (mostly download wait)

---

## Problem Statement

The user runs five LLM services on a personal M5 Max laptop: a dedicated server for the primary coding agent, a router serving multiple models on-demand, a VibeThinker reasoning model, an embedding server, and a KV-cache proxy (proxycache). The goal is to:

1. **Add three new models** to the router: Qwen3.8-27B, Muse Glimmer 30B, and Nemotron 3.5 Lightning
2. **Upgrade the dedicated server** from Qwen3.6-27B to Qwen3.8-27B
3. **Keep existing models** for comparison during an evaluation period
4. **Re-enable thinking preservation** now that OpenCode counts reasoning tokens in its context budget
5. **Never sever the brain** — always maintain working model access during the upgrade

This is a high-stakes upgrade because the dedicated server is the primary model used by all OpenCode agents. Any misconfiguration could render the coding assistant unusable until manually rolled back.

---

## Current State

| Service | Port | Model | Status |
|---------|------|-------|--------|
| Dedicated server | :18080 | Qwen3.6-27B (Q8_0, 27 GB) | Always loaded, never sleeps |
| Proxycache | :18083 | → :18080 | KV cache proxy, MODEL_ID=qwen3.6-27b |
| Router | :18082 | 4 models (qwen3.6-27b, qwen3.6-moe, gemma-4-31b, gemma-4-26b-moe) | models-max=1, sleep-idle=600s |
| VibeThinker | :18084 | VibeThinker-3B | Always loaded |
| Embeddings | :18081 | embeddinggemma-300m | Always loaded |

**Key current config details:**
- Dedicated server uses `--chat-template-kwargs '{"preserve_thinking":false}'` — thinking is suppressed
- All existing Qwen/Gemma models use separate MTP GGUF files (`model-draft`)
- Router uses `--chat-template-kwargs '{"preserve_thinking":false}'` — thinking suppressed everywhere
- All models share `temp=0.6, top-p=0.95, top-k=20`
- 9 OpenCode agents point to `llama-server-dedicated/qwen3.6-27b`
- 3 OpenCode agents point to `llama-server/gemma-4-31b`

---

## Design Decisions

### Decision 1: HuggingFace Repository Source — Unsloth GGUF repos

**Choice:** Use `unsloth/` prefixed repositories for all model downloads.

**Alternatives considered:**
- Official repos (`Qwen/`, `meta-llama/`, `nvidia/`) — these host safetensors, not GGUF files
- Third-party GGUF repos — unreliable, may not match llama.cpp expectations

**Rationale:** All existing models in the user's setup come from Unsloth GGUF repos. The official repos contain safetensors which would require manual GGUF conversion. Unsloth repos provide pre-quantized GGUF files with proper metadata for llama.cpp.

### Decision 2: Qwen3.8 MTP — Built-in, same flags as before

**Choice:** Keep `--spec-type draft-mtp --spec-draft-n-max 4` on both router and dedicated server. No separate MTP GGUF file needed.

**Alternatives considered:**
- Remove MTP flags entirely — would disable speculative decoding, losing performance
- Use separate MTP GGUF — Qwen3.8 embeds MTP layers in the main model

**Rationale:** Qwen3.8-27B has MTP layers built into the main GGUF file. The `--spec-type draft-mtp` flag tells llama.cpp to use those built-in layers. This is the same flag pattern used for Qwen3.6, so it's proven to work. The key difference is that no `model-draft` path is needed — the MTP weights are inside the main model file.

### Decision 3: Muse Glimmer — No speculative decoding, conservative sampling

**Choice:** No `spec-type`, no `model-draft`, no DFlash drafter download. Use `temp=0.6, top-p=0.95, top-k=20`.

**Alternatives considered:**
- Download DFlash drafter and configure speculative decoding — the DFlash file exists in the Unsloth repo but Muse Glimmer's architecture may not support it reliably, and it adds complexity without guaranteed benefit
- Use `temp=1.0, top-k=64` — more creative/diverse output but less reliable for coding tasks

**Rationale:** Muse Glimmer is a dense 30B model without built-in MTP. The DFlash drafter is a separate small model that could theoretically enable speculative decoding, but: (a) it adds configuration complexity, (b) the benefit is uncertain without benchmarking, and (c) it wastes 1 GB of disk space if unused. Starting without speculative decoding is the safer default — it can be added later if benchmarks show it helps.

For sampling parameters, `temp=0.6` is consistent with all other models in the setup. `temp=1.0` would produce significantly more random output, which is undesirable for coding tasks where reliability matters. If higher creativity is needed for specific agents, it can be overridden per-request.

### Decision 4: Nemotron — Built-in MTP, no separate drafter, text-only

**Choice:** Use `spec-type = draft-mtp` with built-in MTP layers. No `model-draft` path. No mmproj (text-only model).

**Alternatives considered:**
- Download DFlash/DSpark drafter and configure as `model-draft` — Nemotron has built-in MTP layers in the main GGUF; a separate drafter is unnecessary and would conflict with built-in MTP
- Set `ctx-size = 1048576` (1M) — would consume excessive KV cache memory on the router

**Rationale:** Nemotron 3.5 Lightning has built-in MTP layers embedded in the main GGUF file, similar to Qwen3.8. The DFlash/DSpark drafters are separate small models that could enable additional speculative decoding, but the built-in MTP is sufficient and simpler. The `spec-type = draft-mtp` flag activates the built-in layers.

Context size is set to 131K (not 1M) because: (a) the router uses `--kv-unified` with a shared KV pool, and (b) 1M context at q8_0 would consume ~120 GB of KV cache alone, exceeding available memory. Nemotron can be given a larger context later if needed for specific long-context tasks.

### Decision 5: Thinking preservation — Re-enable everywhere

**Choice:** Remove `--chat-template-kwargs '{"preserve_thinking":false}'` from both dedicated server and router.

**Alternatives considered:**
- Keep it on router, remove from dedicated — creates asymmetry; router smoke tests won't verify thinking
- Keep it everywhere — defeats the purpose of re-enabling thinking

**Rationale:** OpenCode now counts reasoning tokens in its context budget. The original reason for suppressing thinking (OpenCode didn't count thinking tokens, causing context overflow) is resolved. Removing the flag from both servers ensures consistent behavior and allows proper testing of thinking functionality across all access paths.

### Decision 6: presence_penalty — Not added

**Choice:** Do not add `presence-penalty` to Qwen3.8 configuration.

**Alternatives considered:**
- Add `presence-penalty = 1.5` per Unsloth guidance — significant behavioral change, not tested
- Add `presence-penalty = 0.5` as a conservative start — still a behavioral change without local testing

**Rationale:** `presence-penalty` was introduced in one proposal but not the other, with no clear consensus. It's a significant behavioral change that affects output coherence. The existing `temp=0.6, top-p=0.95, top-k=20` sampling profile works well for all current models. If repetition issues arise with Qwen3.8, `presence-penalty` can be added incrementally during the evaluation period.

### Decision 7: Nemotron directory naming — Unsloth convention

**Choice:** Use `NVIDIA-Nemotron-3.5-Lightning-30B-A3B-GGUF` for the directory name.

**Alternatives considered:**
- `Nemotron-3.5-Lightning-GGUF` — shorter but doesn't match Unsloth repo naming

**Rationale:** The Unsloth GGUF repo uses `NVIDIA-Nemotron-3.5-Lightning-30B-A3B-GGUF` as the repo name. Using the same directory name makes it clear where the files came from and matches the GGUF filename inside.

### Decision 8: Agent model assignment — All dedicated agents → Qwen3.8

**Choice:** All 9 agents that currently use `llama-server-dedicated/qwen3.6-27b` switch to `llama-server-dedicated/qwen3.8-27b`. The 3 Gemma agents remain on `llama-server/gemma-4-31b`.

**Alternatives considered:**
- "Dynamic Tiering": route design/critic to Muse Glimmer, plan-impl to Nemotron — adds complexity, introduces cold-start latency for router models, and makes debugging harder
- Keep some agents on Qwen3.6 for comparison — creates confusion about which agent uses which model

**Rationale:** The primary upgrade is Qwen3.8 → dedicated server. All agents should use the new dedicated model to get the benefit of always-warm, cached inference. The router models (Muse Glimmer, Nemotron) are available for manual testing and comparison. Dynamic tiering can be explored later as a separate optimization.

### Decision 9: Phase ordering — Router first, then dedicated

**Choice:** Phase 1: Download → Phase 2: Router update → Phase 3: Dedicated upgrade → Phase 4: OpenCode config → Phase 5: Proxycache → Phase 6: Verification

**Alternatives considered:**
- Dedicated first, then router — risks "severing the brain" if dedicated fails
- Combined single phase — harder to roll back individual components

**Rationale:** Adding models to the router first creates a fallback path. If the dedicated server upgrade fails, OpenCode can temporarily route through the router (with cold-start latency) while the issue is fixed. Each phase has independent rollback.

### Decision 10: CLI tool — huggingface-cli for compatibility

**Choice:** Use `huggingface-cli download` (not `hf download`).

**Alternatives considered:**
- `hf download` — newer CLI, may not be installed
- `git clone` + manual quantization — unnecessary complexity when GGUF files are available

**Rationale:** `huggingface-cli` is the established command that works with all versions of `huggingface_hub`. `hf` is a newer alias that requires `huggingface_hub >= 2.0`. Using `huggingface-cli` ensures compatibility with existing installations.

---

## Memory Budget

### Resident Memory (always loaded)

| Service | Model | Weights (Q8_0) | KV Cache | Total |
|---------|-------|----------------|----------|-------|
| Dedicated :18080 | Qwen3.8-27B | ~27 GB | ~8 GB (262K ctx, 2 parallel, q8_0) | ~35 GB |
| VibeThinker :18084 | VibeThinker-3B | ~3.1 GB | ~0.3 GB (128K ctx) | ~3.4 GB |
| Embeddings :18081 | embeddinggemma-300m | ~0.3 GB | negligible | ~0.5 GB |
| Proxycache :18083 | Python process | — | — | ~0.5 GB |
| **Resident subtotal** | | | | **~39.4 GB** |

### Router Memory (models-max=1, one at a time)

| Model | Weights (Q8_0) | KV Cache (128K, q8_0) | Total |
|-------|----------------|----------------------|-------|
| qwen3.6-27b | ~27 GB | ~4 GB | ~31 GB |
| qwen3.6-moe | ~20 GB | ~1.2 GB | ~21 GB |
| gemma-4-31b | ~31 GB | ~30 GB (60 layers × 2048 head dim) | ~61 GB |
| gemma-4-26b-moe | ~26 GB | ~7.6 GB | ~34 GB |
| qwen3.8-27b | ~27 GB | ~4 GB (16 attn layers × 4 KV × 256) | ~31 GB |
| muse-glimmer-30b | ~30 GB | ~8 GB (dense 30B, moderate attn) | ~38 GB |
| nemotron-3.5-lightning | ~32 GB | ~4 GB (MoE, 3B active, low KV) | ~36 GB |

### Peak Memory Scenarios

| Scenario | Resident | Router (peak) | **Total** | Headroom |
|----------|----------|---------------|-----------|----------|
| Best case (qwen3.6-moe on router) | 39.4 GB | 21 GB | **~60 GB** | ~68 GB |
| Typical (qwen3.8-27b on router) | 39.4 GB | 31 GB | **~70 GB** | ~58 GB |
| Worst case (gemma-4-31b on router) | 39.4 GB | 61 GB | **~100 GB** | ~28 GB |
| macOS overhead | — | — | ~15-25 GB | — |
| **Usable headroom (worst case)** | | | **~3-13 GB** | Tight but safe |

**Verdict:** All models fit with `models-max=1`. The worst case (gemma-4-31b on router + all resident services) uses ~100 GB of 128 GB, leaving 28 GB before macOS overhead. This is tight but safe — macOS typically uses 15-25 GB. If memory pressure occurs, the router's LRU eviction will unload the model.

**KV cache math for Qwen3.8-27B (dedicated, 262K context):**
- 64 layers: 16×(3× DeltaNet + 1× Gated Attention); only 16 attention layers produce KV
- Gated Attention: 4 KV heads × 256 head dim
- KV per token: 16 × 4 × 256 × 2 = 32,768 values (32 KiB @ q8_0, 64 KiB @ f16)
- KV cache @ 262K ctx, q8_0: 262,144 × 32,768 / 1,048,576 = ~8.0 GB
- Total GPU memory: ~27 GB weights + ~8 GB KV = ~35 GB

---

## Download Plan

All downloads use `unsloth/` prefixed repositories. Run from `~/Models/`.

### Qwen3.8-27B

```bash
mkdir -p ~/Models/Qwen3.8-27B-GGUF

# Main model (~27 GB, MTP built-in)
huggingface-cli download unsloth/Qwen3.8-27B-GGUF \
  Qwen3.8-27B-Q8_0.gguf \
  --local-dir ~/Models/Qwen3.8-27B-GGUF

# Vision projector (~884 MB)
huggingface-cli download unsloth/Qwen3.8-27B-GGUF \
  mmproj-F16.gguf \
  --local-dir ~/Models/Qwen3.8-27B-GGUF
```

**Verification:**
```bash
ls -lh ~/Models/Qwen3.8-27B-GGUF/
# Expected: Qwen3.8-27B-Q8_0.gguf (~27G), mmproj-F16.gguf (~884M)
```

### Muse Glimmer 30B

```bash
mkdir -p ~/Models/Muse-Glimmer-30B-GGUF

# Main model (~30 GB, no MTP)
huggingface-cli download unsloth/Muse-Glimmer-30B-GGUF \
  Muse-Glimmer-30B-Q8_0.gguf \
  --local-dir ~/Models/Muse-Glimmer-30B-GGUF

# Vision projector (~1 GB)
huggingface-cli download unsloth/Muse-Glimmer-30B-GGUF \
  mmproj-Muse-Glimmer-30B-Q8_0.gguf \
  --local-dir ~/Models/Muse-Glimmer-30B-GGUF
```

**Verification:**
```bash
ls -lh ~/Models/Muse-Glimmer-30B-GGUF/
# Expected: Muse-Glimmer-30B-Q8_0.gguf (~30G), mmproj-Muse-Glimmer-30B-Q8_0.gguf (~1G)
```

### Nemotron 3.5 Lightning

```bash
mkdir -p ~/Models/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-GGUF

# Main model (~32 GB, MTP built-in, text-only — no mmproj)
huggingface-cli download unsloth/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-GGUF \
  NVIDIA-Nemotron-3.5-Lightning-30B-A3B-Q8_0.gguf \
  --local-dir ~/Models/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-GGUF
```

**Verification:**
```bash
ls -lh ~/Models/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-GGUF/
# Expected: NVIDIA-Nemotron-3.5-Lightning-30B-A3B-Q8_0.gguf (~32G)
```

### Post-download verification

```bash
# Verify GGUF metadata for each model
for model in \
  ~/Models/Qwen3.8-27B-GGUF/Qwen3.8-27B-Q8_0.gguf \
  ~/Models/Muse-Glimmer-30B-GGUF/Muse-Glimmer-30B-Q8_0.gguf \
  ~/Models/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-GGUF/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-Q8_0.gguf; do
  echo "=== $(basename $(dirname $model)) ==="
  llama-llama-bench -m "$model" -c 1 --verbose 2>&1 | head -30
  echo
done

# Check remaining disk space
df -h /Users/evantd
# Expected: ≥60 GB remaining (started with ~1.3 TB, used ~90 GB)
```

---

## Config Changes

### File 1: `~/Models/models-personal.ini` (Router model config)

Complete file contents:

```ini
; llama-server router-mode presets
; Launch: llama-server --models-preset ~/Models/models-personal.ini (via ~/Models/llama-server-personal.sh)
;
; Topology:
;   :18080 Dedicated server (Qwen3.8-27B after upgrade)
;   :18081 Embeddings (standalone)
;   :18082 llama-server router (this file)
;   :18083 Proxycache → :18080
;   :18084 VibeThinker-3B
;
; KV budget (q8 KV cache; --kv-unified means ctx-size is total shared pool):
;   All models: ctx=131072 (half of 262K training context)
;   NOTE: Quality degrades noticeably around 130K (model rumination, looping).
;   Setting ctx-size to 131K triggers compaction earlier, keeping quality stable.
;   Training context is 262144 — setting higher gets silently capped by llama.cpp.
;   EXCEPTION: Nemotron 3.5 Lightning has 1M training context; 131K is conservative.
; Router holds 1 model resident (--models-max 1); LRU evicts the rest.
;
; Defaults applied to every model. Per-section overrides take precedence.
; Router controls/overrides: host, port, api-key, hf repo, model alias —
; do NOT set those per-section, they will be stripped.
[*]
n-gpu-layers = 99
cache-type-k = q8_0
cache-type-v = q8_0
jinja = true

; === EXISTING MODELS ===

; Qwen3.6-27B: dense, best accuracy baseline (82.5% on harness-bench)
; NOTE: Requires separate MTP GGUF file.
[qwen3.6-27b]
model = /Users/evantd/Models/Qwen3.6-27B-MTP-GGUF/Qwen3.6-27B-Q8_0.gguf
mmproj = /Users/evantd/Models/Qwen3.6-27B-MTP-GGUF/mmproj-F16.gguf
alias = qwen3.6-27b
parallel = 1
ctx-size = 131072
temp = 0.6
top-p = 0.95
top-k = 20
spec-type = draft-mtp
spec-draft-n-max = 4

; Qwen3.6-35B-A3B (MoE, 3B active): fast generation with decent accuracy (80%)
[qwen3.6-moe]
model = /Users/evantd/Models/Qwen3.6-35B-A3B-MTP-GGUF/Qwen3.6-35B-A3B-Q8_0.gguf
mmproj = /Users/evantd/Models/Qwen3.6-35B-A3B-MTP-GGUF/mmproj-F16.gguf
alias = qwen3.6-moe
parallel = 1
ctx-size = 131072
temp = 0.6
top-p = 0.95
top-k = 20
spec-type = draft-mtp
spec-draft-n-max = 4

; Gemma 4 31B: strong reasoning (81.2%), dense
[gemma-4-31b]
model = /Users/evantd/Models/gemma-4-31b-it-GGUF/gemma-4-31B-it-Q8_0.gguf
mmproj = /Users/evantd/Models/gemma-4-31b-it-GGUF/mmproj-F16.gguf
model-draft = /Users/evantd/Models/gemma-4-31b-it-GGUF/MTP/gemma-4-31B-it-Q8_0-MTP.gguf
alias = gemma-4-31b
parallel = 1
ctx-size = 131072
temp = 0.6
top-p = 0.95
top-k = 20
spec-type = draft-mtp
spec-draft-n-max = 4

; Gemma 4 26B-A4B (MoE, 4B active): fast (~397s/task)
[gemma-4-26b-moe]
model = /Users/evantd/Models/gemma-4-26B-A4B-it-GGUF/gemma-4-26B-A4B-it-Q8_0.gguf
mmproj = /Users/evantd/Models/gemma-4-26B-A4B-it-GGUF/mmproj-F16.gguf
model-draft = /Users/evantd/Models/gemma-4-26B-A4B-it-GGUF/MTP/gemma-4-26B-A4B-it-Q8_0-MTP.gguf
alias = gemma-4-26b-moe
parallel = 1
ctx-size = 131072
temp = 0.6
top-p = 0.95
top-k = 20
spec-type = draft-mtp
spec-draft-n-max = 4

; === NEW MODELS ===

; Qwen3.8-27B: upgraded from Qwen3.6-27B
; Key changes: MTP is BUILT-IN (no separate MTP GGUF), configurable reasoning_effort
; SWE-bench Pro: 61.7% (vs 53.5% for Qwen3.6)
; Vision-language model with flexible thinking control.
;qwen3.8-27b]
model = /Users/evantd/Models/Qwen3.8-27B-GGUF/Qwen3.8-27B-Q8_0.gguf
mmproj = /Users/evantd/Models/Qwen3.8-27B-GGUF/mmproj-F16.gguf
alias = qwen3.8-27b
parallel = 1
ctx-size = 131072
temp = 0.6
top-p = 0.95
top-k = 20
spec-type = draft-mtp
spec-draft-n-max = 4

; Muse Glimmer 30B: Meta's dense 30B, Apache 2.0
; No MTP, no speculative decoding. Controllable reasoning via system prompt.
; Strong multimodal capabilities.
[muse-glimmer-30b]
model = /Users/evantd/Models/Muse-Glimmer-30B-GGUF/Muse-Glimmer-30B-Q8_0.gguf
mmproj = /Users/evantd/Models/Muse-Glimmer-30B-GGUF/mmproj-Muse-Glimmer-30B-Q8_0.gguf
alias = muse-glimmer-30b
parallel = 1
ctx-size = 131072
temp = 0.6
top-p = 0.95
top-k = 20

; Nemotron 3.5 Lightning: NVIDIA MoE (30B total, 3B active), agent-optimized
; Built-in MTP. Text-only (no vision). 1M training context (using 131K conservatively).
[nemotron-3.5-lightning]
model = /Users/evantd/Models/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-GGUF/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-Q8_0.gguf
alias = nemotron-3.5-lightning
parallel = 1
ctx-size = 131072
temp = 0.6
top-p = 0.95
top-k = 20
spec-type = draft-mtp
spec-draft-n-max = 4
```

**Changes from current:**
- Added 3 new model sections: `qwen3.8-27b`, `muse-glimmer-30b`, `nemotron-3.5-lightning`
- Qwen3.8 section: `spec-type = draft-mtp` + `spec-draft-n-max = 4` but NO `model-draft` (MTP built-in)
- Muse Glimmer: NO `spec-type`, NO `model-draft`, NO `spec-draft-n-max` (no MTP support)
- Nemotron: `spec-type = draft-mtp` + `spec-draft-n-max = 4` but NO `model-draft` (MTP built-in), NO `mmproj` (text-only)
- All existing 4 model sections preserved unchanged
- All new models use `temp=0.6, top-p=0.95, top-k=20` for consistency

### File 2: `~/Models/llama-server-personal.sh` (Service management script)

The complete file is provided below. Key changes from current version:

1. **`DEDICATED_MODEL`** → `~/Models/Qwen3.8-27B-GGUF/Qwen3.8-27B-Q8_0.gguf`
2. **`--alias`** → `qwen3.8-27b`
3. **Removed** `--chat-template-kwargs '{"preserve_thinking":false}'` from `start_dedicated()` — thinking enabled by default
4. **Removed** `--chat-template-kwargs '{"preserve_thinking":false}'` from `start_router()` — thinking enabled everywhere
5. **Retained** `--spec-type draft-mtp --spec-draft-n-max 4` on dedicated server — Qwen3.8 has built-in MTP
6. **No** `--presence-penalty` added — kept consistent with existing models
7. **`status()`** function: router metrics check updated to `qwen3.8-27b`

Complete file:

```bash
#!/bin/bash
# llama-server management script (personal laptop variant)
# Usage: llama-server-personal.sh {start|stop|restart|restart-dedicated|restart-router|status|log|embed-log|dedicated-log}
#
# Manages five services (see BlueBarb doc § "Local model server topology"):
#   - Embeddings           (LLAMA_EMBED_PORT,     default 18081): embeddinggemma-300m
#   - Dedicated server     (LLAMA_DEDICATED_PORT, default 18080): Qwen3.8-27B
#   - llama-server router  (LLAMA_INFERENCE_PORT, default 18082): chat models per models-personal.ini
#   - VibeThinker          (LLAMA_VIBE_PORT,      default 18084): VibeThinker-3B
#   - Proxycache           (LLAMA_PROXYCACHE_PORT,default 18083): KV cache proxy → dedicated
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
# Qwen3.8-27B: upgraded dense model with built-in MTP, reasoning_effort, vision
# ~27GB Q8_0 + ~8GB KV cache (262K ctx, 2 parallel, q8) = ~35GB total
#
# KV cache math — sliding window layers DO get cached (window limits attention,
# not storage). All attention layers count, not just global.
#
# Qwen3.8-27B (dense, per https://huggingface.co/unsloth/Qwen3.8-27B-GGUF):
#   - 64 layers: 16×(3× DeltaNet + 1× Gated Attention); only 16 attn layers
#   - Gated Attention: 4 KV heads × 256 head dim
#   - KV/token: 16 × 4 × 256 × 2 = 32,768 values (32 KiB @ q8, 64 KiB @ f16)
#
# KV cache size by context (q8_0):
#   Qwen3.8-27B | 128K: ~4.0 GB | 262K: ~8.0 GB | 524K: ~16.0 GB
#
# Total GPU memory ≈ model weights + KV cache (q8_0):
#   Qwen3.8-27B @ 262K: ~35 GB
#
DEDICATED_MODEL="$HOME/Models/Qwen3.8-27B-GGUF/Qwen3.8-27B-Q8_0.gguf"
DEDICATED_PORT="${LLAMA_DEDICATED_PORT:-18080}"
DEDICATED_LOG="$HOME/Models/dedicated-server.log"
DEDICATED_PIDFILE="$HOME/Models/dedicated-server.pid"

# VibeThinker 3B dedicated server (always loaded, never sleeps)
# Reasoning-specialized small model for design feedback loop.
# ~3.1GB Q8_0, negligible memory cost to keep resident.
VIBE_MODEL="$HOME/Models/VibeThinker-3B-GGUF/vibethinker-3b-q8_0.gguf"
VIBE_PORT="${LLAMA_VIBE_PORT:-18084}"
VIBE_LOG="$HOME/Models/vibe-server.log"
VIBE_PIDFILE="$HOME/Models/vibe-server.pid"

# Proxycache (KV cache proxy for dedicated server)
# Sits between OpenCode and the dedicated server on port 18083.
# Restores evicted KV cache from disk to avoid full re-prefill.
PROXYCACHE_DIR="$HOME/Models/proxycache"
PROXYCACHE_PORT="${LLAMA_PROXYCACHE_PORT:-18083}"
PROXYCACHE_LOG="$HOME/Models/proxycache.log"
PROXYCACHE_PIDFILE="$HOME/Models/proxycache.pid"

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
    echo "Starting dedicated server on $HOST:$DEDICATED_PORT (Qwen3.8-27B, always loaded, never sleeps)..."
    nohup bash -c "stdbuf -oL -eL llama-server \
        --model \"$DEDICATED_MODEL\" \
        --port \"$DEDICATED_PORT\" \
        --host \"$HOST\" \
        --alias qwen3.8-27b \
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
        --no-kv-unified \
        --slot-save-path \"$HOME/Models/slot-cache\" \
        --spec-type draft-mtp \
        --spec-draft-n-max 4 \
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

start_vibe() {
    if [ -f "$VIBE_PIDFILE" ] && kill -0 "$(cat "$VIBE_PIDFILE")" 2>/dev/null; then
        echo "VibeThinker server already running (PID $(cat "$VIBE_PIDFILE"))"
        return 0
    fi
    if [ ! -f "$VIBE_MODEL" ]; then
        echo "VibeThinker model not found: $VIBE_MODEL"
        return 1
    fi
    wait_for_port_free "$VIBE_PORT" 10
    echo "Starting VibeThinker server on $HOST:$VIBE_PORT..."
    nohup bash -c "stdbuf -oL -eL llama-server \
        --model \"$VIBE_MODEL\" \
        --port \"$VIBE_PORT\" \
        --host \"$HOST\" \
        --alias vibethinker-3b \
        --ctx-size 131072 \
        --n-gpu-layers 99 \
        --parallel 1 \
        --temp 1.0 \
        --top-p 0.95 \
        --top-k -1 \
        --cache-type-k q8_0 \
        --cache-type-v q8_0 \
        --jinja \
        --log-timestamps \
        --log-verbosity \"$LOG_VERBOSITY\" \
        --metrics \
        --perf \
        --kv-unified \
        2>&1 | LOG_NAME=\"vibe-server.log\" python3 \"$HOME/Models/log_wrapper.py\"" >/dev/null 2>/dev/null &
    echo $! > "$VIBE_PIDFILE"
    sleep 2
    if kill -0 "$(cat "$VIBE_PIDFILE")" 2>/dev/null; then
        echo "VibeThinker server started (PID $(cat "$VIBE_PIDFILE"))"
    else
        echo "VibeThinker server failed. Check $VIBE_LOG"
        rm -f "$VIBE_PIDFILE"
        return 1
    fi
}

stop_vibe() {
    stop_one "VibeThinker server" "$VIBE_PIDFILE" "" "$VIBE_PORT"
}

start_proxycache() {
    if [ -f "$PROXYCACHE_PIDFILE" ] && kill -0 "$(cat "$PROXYCACHE_PIDFILE")" 2>/dev/null; then
        echo "proxycache already running (PID $(cat "$PROXYCACHE_PIDFILE"))"
        return 0
    fi
    wait_for_port_free "$PROXYCACHE_PORT" 5
    echo "Starting proxycache on $HOST:$PROXYCACHE_PORT..."
    nohup bash -c "source $PROXYCACHE_DIR/venv/bin/activate && \
        source $PROXYCACHE_DIR/env.sh && \
        cd $PROXYCACHE_DIR && \
        python3 proxycache.py \
        2>&1 | LOG_NAME='proxycache.log' python3 '$HOME/Models/log_wrapper.py'" >/dev/null 2>/dev/null &
    echo $! > "$PROXYCACHE_PIDFILE"
    sleep 2
    if kill -0 "$(cat "$PROXYCACHE_PIDFILE")" 2>/dev/null; then
        echo "proxycache started (PID $(cat "$PROXYCACHE_PIDFILE"))"
    else
        echo "proxycache failed. Check $PROXYCACHE_LOG"
        rm -f "$PROXYCACHE_PIDFILE"
        return 1
    fi
}

stop_proxycache() {
    stop_one "proxycache" "$PROXYCACHE_PIDFILE" "" "$PROXYCACHE_PORT"
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
    start_vibe
    start_proxycache
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
    stop_one "proxycache" "$PROXYCACHE_PIDFILE" "" "$PROXYCACHE_PORT"
    stop_one "VibeThinker server" "$VIBE_PIDFILE" "" "$VIBE_PORT"
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
        if curl -s "http://$HOST:$PORT/metrics?model=qwen3.8-27b" >/dev/null 2>&1; then
            echo "  metrics endpoint: available"
        else
            echo "  metrics endpoint: not responding (may need --metrics flag)"
        fi
    else
        echo "llama-server router not running"
    fi
    if [ -f "$VIBE_PIDFILE" ] && kill -0 "$(cat "$VIBE_PIDFILE")" 2>/dev/null; then
        echo "VibeThinker       running (PID $(cat "$VIBE_PIDFILE")) :$VIBE_PORT"
    else
        echo "VibeThinker       not running"
    fi
    if [ -f "$PROXYCACHE_PIDFILE" ] && kill -0 "$(cat "$PROXYCACHE_PIDFILE")" 2>/dev/null; then
        echo "proxycache          running (PID $(cat "$PROXYCACHE_PIDFILE")) :$PROXYCACHE_PORT"
        if curl -s "http://$HOST:$PROXYCACHE_PORT/v1/models" >/dev/null 2>&1; then
            echo "  /v1/models endpoint: available"
        else
            echo "  /v1/models endpoint: not responding"
        fi
    else
        echo "proxycache          not running"
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

restart_proxycache() {
    stop_proxycache
    sleep 2
    start_proxycache
}

case "${1:-status}" in
    start)       start ;;
    stop)        stop ;;
    restart)     stop; sleep 5; start ;;
    restart-dedicated) restart_dedicated ;;
    restart-router)    restart_router ;;
    restart-proxycache) restart_proxycache ;;
    status)      status ;;
    log)         tail -f "$DEDICATED_LOG" ;;
    embed-log)   tail -f "$EMBED_LOG" ;;
    dedicated-log) tail -f "$DEDICATED_LOG" ;;
    proxycache-log) tail -f "$PROXYCACHE_LOG" ;;
    *)           echo "Usage: $0 {start|stop|restart|restart-dedicated|restart-router|status|log|embed-log|dedicated-log|proxycache-log}" ;;
esac
```

### File 3: `~/Models/proxycache/env.sh` (Proxycache environment)

Complete file contents:

```bash
# Proxycache environment configuration
# Source this file before starting proxycache

export BACKENDS='[{"url": "http://127.0.0.1:18080", "n_slots": 2}]'
export PORT=18083
export META_DIR="$HOME/Models/proxycache-meta"
export MODEL_ID="qwen3.8-27b"
export LCP_TH=0.95
export BIG_THRESHOLD_WORDS=500
export WORDS_PER_BLOCK=100
export LOG_LEVEL=INFO

# Cache cleanup
export BIN_SAVE_PATH="$HOME/Models/slot-cache"
export MAX_CACHE_SIZE="100GB"
```

**Only change:** `MODEL_ID` from `qwen3.6-27b` to `qwen3.8-27b`.

**Important:** Changing `MODEL_ID` invalidates the existing proxycache KV cache on disk. The proxycache will treat all requests as cache misses until new cache entries are built for `qwen3.8-27b`. This causes temporary latency increase during the first few conversations. No manual cleanup is needed — the `MAX_CACHE_SIZE` setting handles old file eviction.

### File 4: `~/.config/opencode/opencode.json` (OpenCode provider config)

Complete file contents:

```json
{
  "$schema":       "https://opencode.ai/config.json",
  "permission":    "allow",
  "model":         "llama-server-dedicated/qwen3.8-27b",
  "default_agent": "assistant",
  "instructions": [
    "instructions/common.md"
  ],
  "enabled_providers": [
    "llama-server-dedicated",
    "llama-server-vibe",
    "llama-server"
  ],
  "provider": {
    "llama-server-dedicated": {
      "npm":  "@ai-sdk/openai-compatible",
      "name": "llama-server dedicated (via proxycache)",
      "options": {
        "baseURL": "http://localhost:{env:LLAMA_PROXYCACHE_PORT}/v1"
      },
      "models": {
        "qwen3.8-27b": {
          "name": "qwen3.8-27B Dense (always-loaded, built-in MTP) — default",
          "modalities": {
            "input": ["text", "image"]
          },
          "limit": {
            "context": 131072,
            "output":  32768
          }
        }
      }
    },
    "llama-server-vibe": {
      "npm":  "@ai-sdk/openai-compatible",
      "name": "VibeThinker-3B dedicated server",
      "options": {
        "baseURL": "http://localhost:18084/v1"
      },
      "models": {
        "vibethinker-3b": {
          "name": "VibeThinker-3B Reasoning-specialized (dedicated server)",
          "limit": {
            "context": 131072,
            "output":  32768
          }
        }
      }
    },
    "llama-server": {
      "npm":  "@ai-sdk/openai-compatible",
      "name": "llama-server router (direct)",
      "options": {
        "baseURL": "http://localhost:{env:LLAMA_INFERENCE_PORT}/v1"
      },
      "models": {
        "qwen3.8-27b": {
          "name": "qwen3.8-27B Dense (on-demand via router, built-in MTP)",
          "modalities": {
            "input": ["text", "image"]
          },
          "limit": {
            "context": 131072,
            "output":  32768
          }
        },
        "qwen3.6-27b": {
          "name": "qwen3.6-27B Dense (on-demand via router, legacy)",
          "modalities": {
            "input": ["text", "image"]
          },
          "limit": {
            "context": 131072,
            "output":  32768
          }
        },
        "muse-glimmer-30b": {
          "name": "Muse Glimmer 30B Dense (Apache 2.0, multimodal)",
          "modalities": {
            "input": ["text", "image"]
          },
          "limit": {
            "context": 131072,
            "output":  32768
          }
        },
        "nemotron-3.5-lightning": {
          "name": "Nemotron 3.5 Lightning MoE (agent-optimized, built-in MTP)",
          "limit": {
            "context": 131072,
            "output":  32768
          }
        },
        "gemma-4-31b": {
          "name": "gemma-4-31B-it Strong reasoning",
          "limit": {
            "context": 131072,
            "output":  32768
          }
        },
        "gemma-4-26b-moe": {
          "name": "gemma-4-26B-A4B-it MoE (4B active) — fast",
          "limit": {
            "context": 131072,
            "output":  32768
          }
        },
        "qwen3.6-moe": {
          "name": "qwen3.6-35B-A3B MoE (3B active) — fast fallback",
          "modalities": {
            "input": ["text", "image"]
          },
          "limit": {
            "context": 131072,
            "output":  32768
          }
        }
      }
    }
  },
  "mcp": {"mcp-optimizer": {"url": "http://localhost:50206/mcp", "type": "remote"}}
}
```

**Changes from current:**
1. Default `model` → `llama-server-dedicated/qwen3.8-27b`
2. Dedicated provider: model key changed from `qwen3.6-27b` to `qwen3.8-27b`; added `modalities` for vision
3. Router provider: added `qwen3.8-27b`, `muse-glimmer-30b`, `nemotron-3.5-lightning`
4. Router provider: kept `qwen3.6-27b` for comparison (labeled "legacy")
5. `nemotron-3.5-lightning`: no `modalities` block (text-only model)

### File 5: Agent config files

All 9 agents that reference `llama-server-dedicated/qwen3.6-27b` change to `llama-server-dedicated/qwen3.8-27b`. The 3 Gemma agents (`design-gemma`, `critic-gemma`, `plan-impl-gemma`) are **unchanged** — they continue to use `llama-server/gemma-4-31b`.

Batch update command:

```bash
for f in assistant design plan-impl critic implement orchestrator synthesizer bluebarb daily-planner; do
  sed -i '' 's|llama-server-dedicated/qwen3.6-27b|llama-server-dedicated/qwen3.8-27b|g' \
    ~/.config/opencode/agents/${f}.md
done
```

**Verification:**
```bash
grep -r "model:" ~/.config/opencode/agents/
# Expected:
#   assistant.md:       llama-server-dedicated/qwen3.8-27b
#   design.md:          llama-server-dedicated/qwen3.8-27b
#   plan-impl.md:       llama-server-dedicated/qwen3.8-27b
#   critic.md:          llama-server-dedicated/qwen3.8-27b
#   implement.md:       llama-server-dedicated/qwen3.8-27b
#   orchestrator.md:    llama-server-dedicated/qwen3.8-27b
#   synthesizer.md:     llama-server-dedicated/qwen3.8-27b
#   bluebarb.md:        llama-server-dedicated/qwen3.8-27b
#   daily-planner.md:   llama-server-dedicated/qwen3.8-27b
#   design-gemma.md:    llama-server/gemma-4-31b  (unchanged)
#   critic-gemma.md:    llama-server/gemma-4-31b  (unchanged)
#   plan-impl-gemma.md: llama-server/gemma-4-31b  (unchanged)
```

**Note on `reasoning_effort`:** Qwen3.8 supports `reasoning_effort` (none/low/medium/high/xhigh) as a per-request parameter. If OpenCode supports `reasoning_effort` as a YAML frontmatter field in agent files, add it per-agent. If not, it can be passed via system prompt or API `extra_body`. This is an optional enhancement that can be added during the evaluation period.

---

## Upgrade Sequence

### Pre-Flight Checks (5 min)

**Goal:** Verify current system is healthy before any changes.

```bash
# 1. Verify all services running
~/Models/llama-server-personal.sh status

# 2. Verify all models accessible
curl -s http://127.0.0.1:18083/v1/models | python3 -m json.tool
curl -s http://127.0.0.1:18082/v1/models | python3 -m json.tool
curl -s http://127.0.0.1:18084/v1/models | python3 -m json.tool

# 3. Quick smoke test — send a request to each service
curl -s http://127.0.0.1:18083/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen3.6-27b","messages":[{"role":"user","content":"Say hello"}],"max_tokens":10}' | python3 -m json.tool

# 4. Check disk space (need ~100 GB free for 3 new Q8_0 models)
df -h ~/Models/

# 5. Check llama.cpp version (need 10270+ for built-in MTP)
llama-server --version

# 6. Check huggingface-cli availability
huggingface-cli --version

# 7. Back up current configs (timestamped for uniqueness)
TIMESTAMP=$(date +%Y%m%d%H%M%S)
cp ~/Models/models-personal.ini ~/Models/models-personal.ini.bak.$TIMESTAMP
cp ~/Models/llama-server-personal.sh ~/Models/llama-server-personal.sh.bak.$TIMESTAMP
cp ~/Models/proxycache/env.sh ~/Models/proxycache/env.sh.bak.$TIMESTAMP
cp ~/.config/opencode/opencode.json ~/.config/opencode/opencode.json.bak.$TIMESTAMP
for f in ~/.config/opencode/agents/*.md; do
  cp "$f" "${f}.bak.$TIMESTAMP"
done
echo "Backups created with timestamp: $TIMESTAMP"
```

**Rollback point:** All configs backed up. If anything goes wrong at any phase, restore from `.bak.$TIMESTAMP` files.

---

### Phase 1: Download New Models (20-40 min)

**Goal:** Download all 3 new models. No service disruption.

Execute the download commands from the Download Plan section above. All three downloads are independent and can run sequentially.

**Verification:**
```bash
echo "=== Qwen3.8-27B ===" && ls -lh ~/Models/Qwen3.8-27B-GGUF/
echo "=== Muse Glimmer ===" && ls -lh ~/Models/Muse-Glimmer-30B-GGUF/
echo "=== Nemotron 3.5 ===" && ls -lh ~/Models/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-GGUF/
echo "=== Disk remaining ===" && df -h /Users/evantd
```

**Rollback:** `rm -rf ~/Models/Qwen3.8-27B-GGUF ~/Models/Muse-Glimmer-30B-GGUF ~/Models/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-GGUF`

---

### Phase 2: Router Config Update (3 min)

**Goal:** Router serves new models alongside existing ones. Dedicated server untouched.

**Step 2.1:** Write the updated `models-personal.ini` (from File 1 above).

**Step 2.2:** Restart router only:
```bash
~/Models/llama-server-personal.sh restart-router
```

**Step 2.3:** Verify router lists all 7 models:
```bash
sleep 5
curl -s http://127.0.0.1:18082/v1/models | python3 -c "
import sys, json
models = json.loads(sys.stdin.read())['data']
for m in sorted(models, key=lambda x: x['id']):
    print(f\"  {m['id']}\")
"
```

**Expected output (7 models):**
```
  gemma-4-26b-moe
  gemma-4-31b
  muse-glimmer-30b
  nemotron-3.5-lightning
  qwen3.6-27b
  qwen3.6-moe
  qwen3.8-27b
```

**Step 2.4:** Smoke test each new model:
```bash
for model in qwen3.8-27b muse-glimmer-30b nemotron-3.5-lightning; do
  echo "=== Testing $model ==="
  curl -s http://127.0.0.1:18082/v1/chat/completions \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"$model\",\"messages\":[{\"role\":\"user\",\"content\":\"Say hello in one word\"}],\"max_tokens\":5}" | python3 -c "import sys,json; print(json.loads(sys.stdin.read())['choices'][0]['message']['content'])"
  echo
done
```

**Step 2.5:** Verify old models still work:
```bash
for model in qwen3.6-27b qwen3.6-moe gemma-4-31b gemma-4-26b-moe; do
  echo "=== Testing $model ==="
  curl -s http://127.0.0.1:18082/v1/chat/completions \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"$model\",\"messages\":[{\"role\":\"user\",\"content\":\"Say hello in one word\"}],\"max_tokens\":5}" | python3 -c "import sys,json; print(json.loads(sys.stdin.read())['choices'][0]['message']['content'])"
  echo
done
```

**Step 2.6:** Verify dedicated server still running (untouched):
```bash
~/Models/llama-server-personal.sh status
# Dedicated server should still show as running with qwen3.6-27b
```

**Rollback:**
```bash
cp ~/Models/models-personal.ini.bak.$TIMESTAMP ~/Models/models-personal.ini
~/Models/llama-server-personal.sh restart-router
```

---

### Phase 3: Dedicated Server Upgrade (5 min)

**Goal:** Primary dedicated server now uses Qwen3.8-27B.

**Strategy:** The dedicated server downtime is ~30 seconds. If actively using OpenCode during the upgrade, temporarily redirect the default model to the router path (`llama-server/qwen3.6-27b`) before stopping the dedicated server. If not actively using, skip the redirect.

**Step 3.1 (optional):** If actively using OpenCode, temporarily change the default model in `opencode.json`:
```json
"model": "llama-server/qwen3.6-27b"
```
Reload OpenCode. This routes through the router (with cold-start latency) during the brief dedicated server downtime.

**Step 3.2:** Stop dedicated server:
```bash
~/Models/llama-server-personal.sh stop_one "Dedicated server" "$HOME/Models/dedicated-server.pid" "" 18080
```

**Step 3.3:** Write the updated `llama-server-personal.sh` (from File 2 above).

**Step 3.4:** Start new dedicated server:
```bash
~/Models/llama-server-personal.sh start_dedicated
```

**Step 3.5:** Verify dedicated server:
```bash
sleep 5
# Check model name
curl -s http://127.0.0.1:18080/v1/models | python3 -c "
import sys, json
for m in json.loads(sys.stdin.read())['data']:
    print(f\"  Model: {m['id']}\")
"

# Quick chat test
curl -s http://127.0.0.1:18080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"What model are you? Answer in 3 words."}],"max_tokens":10}' \
  | python3 -c "import sys,json; print(json.loads(sys.stdin.read())['choices'][0]['message']['content'])"
```

**Expected:** Model ID shows `qwen3.8-27b`, response is coherent.

**Step 3.6 (if redirected in 3.1):** Revert `opencode.json` default model back to dedicated:
```json
"model": "llama-server-dedicated/qwen3.8-27b"
```

**Rollback:**
```bash
cp ~/Models/llama-server-personal.sh.bak.$TIMESTAMP ~/Models/llama-server-personal.sh
~/Models/llama-server-personal.sh restart-dedicated
```

---

### Phase 4: OpenCode Config Update (3 min)

**Goal:** OpenCode addresses the new model. All agents updated.

**Step 4.1:** Write the updated `opencode.json` (from File 4 above).

**Step 4.2:** Update all agent model references:
```bash
for f in assistant design plan-impl critic implement orchestrator synthesizer bluebarb daily-planner; do
  sed -i '' 's|llama-server-dedicated/qwen3.6-27b|llama-server-dedicated/qwen3.8-27b|g' \
    ~/.config/opencode/agents/${f}.md
done
```

**Step 4.3:** Verify agent configs:
```bash
grep -r "model:" ~/.config/opencode/agents/
```

**Step 4.4:** Restart OpenCode to pick up config changes.

**Rollback:**
```bash
cp ~/.config/opencode/opencode.json.bak.$TIMESTAMP ~/.config/opencode/opencode.json
for f in assistant design plan-impl critic implement orchestrator synthesizer bluebarb daily-planner; do
  cp ~/.config/opencode/agents/${f}.md.bak.$TIMESTAMP ~/.config/opencode/agents/${f}.md
done
```

---

### Phase 5: Proxycache Config Update (1 min)

**Goal:** Proxycache aligned with new dedicated model.

**Step 5.1:** Write the updated `proxycache/env.sh` (from File 3 above).

**Step 5.2:** Clear old slot cache (optional but recommended — old cache is for qwen3.6, incompatible with qwen3.8):
```bash
rm -rf ~/Models/slot-cache/*
```

**Step 5.3:** Restart proxycache:
```bash
~/Models/llama-server-personal.sh restart-proxycache
```

**Step 5.4:** Verify proxycache:
```bash
curl -s http://127.0.0.1:18083/v1/models | python3 -c "
import sys, json
for m in json.loads(sys.stdin.read())['data']:
    print(f\"  {m['id']}\")
"
```

**Expected:** `qwen3.8-27b`

**Rollback:**
```bash
cp ~/Models/proxycache/env.sh.bak.$TIMESTAMP ~/Models/proxycache/env.sh
~/Models/llama-server-personal.sh restart-proxycache
```

---

### Phase 6: Verification & Testing (10 min)

**Goal:** Confirm everything works end-to-end.

**6A. All services status:**
```bash
~/Models/llama-server-personal.sh status
```

**Expected:**
```
embedding-server  running (PID ...) :18081
Dedicated server  running (PID ...) :18080
  metrics endpoint: available
llama-server router running (PID ...) :18082
  metrics endpoint: available
VibeThinker       running (PID ...) :18084
proxycache          running (PID ...) :18083
  /v1/models endpoint: available
```

**6B. Memory usage:**
```bash
# Check via Activity Monitor → Memory tab
# Expected: ~70-85 GB used of 128 GB (without router model loaded)
# With router model loaded: ~100 GB peak
```

**6C. Dedicated server smoke test:**
```bash
curl -s http://127.0.0.1:18080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Explain what MTP is in one sentence."}],"max_tokens":50}' \
  | python3 -c "import sys,json; print(json.loads(sys.stdin.read())['choices'][0]['message']['content'])"
```

**6D. Thinking preservation test:**
```bash
# Test that Qwen3.8 produces thinking content by default (preserve_thinking:false removed)
curl -s http://127.0.0.1:18080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"What is 17 × 23? Show your work."}],"max_tokens":200}' \
  | python3 -c "
import sys, json
r = json.loads(sys.stdin.read())
content = r['choices'][0]['message']['content']
print(content[:500])
print()
print(f'Total tokens: {r[\"usage\"][\"total_tokens\"]}')
"
```

**Expected:** Response contains reasoning/thinking content.

**6E. Router new models test:**
```bash
# Test Muse Glimmer
curl -s http://127.0.0.1:18082/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"muse-glimmer-30b","messages":[{"role":"user","content":"What is the capital of Japan? Answer in one word."}],"max_tokens":20}' \
  | python3 -c "import sys,json; print('Muse Glimmer:', json.loads(sys.stdin.read())['choices'][0]['message']['content'])"

# Test Nemotron
curl -s http://127.0.0.1:18082/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"nemotron-3.5-lightning","messages":[{"role":"user","content":"What is the capital of Japan? Answer in one word."}],"max_tokens":20}' \
  | python3 -c "import sys,json; print('Nemotron:', json.loads(sys.stdin.read())['choices'][0]['message']['content'])"
```

**Expected:** Both return "Tokyo".

**6F. Proxycache end-to-end test:**
```bash
curl -s http://127.0.0.1:18083/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Say hello."}],"max_tokens":10}' \
  | python3 -c "import sys,json; print('Proxycache:', json.loads(sys.stdin.read())['choices'][0]['message']['content'])"
```

**6G. OpenCode integration test:**
1. Open OpenCode and verify default model shows as `qwen3.8-27b`
2. Send a test message — should work through proxycache → dedicated
3. Try `@design-gemma` — should route through router to gemma-4-31b
4. Check that thinking content is visible in the response

**6H. Performance benchmark (optional):**
```bash
# Benchmark Qwen3.8-27B dedicated (with MTP)
time curl -s http://127.0.0.1:18080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Write a Python function that implements binary search."}],"max_tokens":500}' \
  -o /dev/null

# Benchmark Nemotron via router (MoE, should be faster)
time curl -s http://127.0.0.1:18082/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"nemotron-3.5-lightning","messages":[{"role":"user","content":"Write a Python function that implements binary search."}],"max_tokens":500}' \
  -o /dev/null
```

---

## Rollback Plan

### Per-Phase Rollback

| Phase | Trigger | Rollback Command |
|-------|---------|-----------------|
| Pre-flight | (backups already made) | N/A |
| Phase 1: Downloads | Wrong files, corruption | `rm -rf ~/Models/Qwen3.8-27B-GGUF ~/Models/Muse-Glimmer-30B-GGUF ~/Models/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-GGUF` |
| Phase 2: Router | Router fails to start, models won't load | `cp ~/Models/models-personal.ini.bak.$TIMESTAMP ~/Models/models-personal.ini && ~/Models/llama-server-personal.sh restart-router` |
| Phase 3: Dedicated | Qwen3.8 fails to load, quality issues | `cp ~/Models/llama-server-personal.sh.bak.$TIMESTAMP ~/Models/llama-server-personal.sh && ~/Models/llama-server-personal.sh restart-dedicated` |
| Phase 4: OpenCode | Config parse error, agents broken | `cp ~/.config/opencode/opencode.json.bak.$TIMESTAMP ~/.config/opencode/opencode.json` + restore agent `.bak.$TIMESTAMP` files |
| Phase 5: Proxycache | Proxycache won't start | `cp ~/Models/proxycache/env.sh.bak.$TIMESTAMP ~/Models/proxycache/env.sh && ~/Models/llama-server-personal.sh restart-proxycache` |
| Phase 6: Testing | (testing only) | N/A |

### Full Rollback (nuclear option)

```bash
# 1. Stop all services
~/Models/llama-server-personal.sh stop

# 2. Restore all configs
cp ~/Models/models-personal.ini.bak.$TIMESTAMP ~/Models/models-personal.ini
cp ~/Models/llama-server-personal.sh.bak.$TIMESTAMP ~/Models/llama-server-personal.sh
cp ~/Models/proxycache/env.sh.bak.$TIMESTAMP ~/Models/proxycache/env.sh
cp ~/.config/opencode/opencode.json.bak.$TIMESTAMP ~/.config/opencode/opencode.json
for f in ~/.config/opencode/agents/*.md; do
  bak="${f}.bak.$TIMESTAMP"
  [ -f "$bak" ] && cp "$bak" "$f"
done

# 3. Start all services
~/Models/llama-server-personal.sh start

# 4. Restart OpenCode

# 5. Verify
~/Models/llama-server-personal.sh status
curl -s http://127.0.0.1:18083/v1/models | python3 -m json.tool
```

### Partial Rollback (dedicated server only, keep router models)

```bash
# Restore dedicated server config and proxycache
cp ~/Models/llama-server-personal.sh.bak.$TIMESTAMP ~/Models/llama-server-personal.sh
cp ~/Models/proxycache/env.sh.bak.$TIMESTAMP ~/Models/proxycache/env.sh

# Restore opencode.json (or manually revert dedicated provider section)
cp ~/.config/opencode/opencode.json.bak.$TIMESTAMP ~/.config/opencode/opencode.json

# Restore agent configs
for f in assistant design plan-impl critic implement orchestrator synthesizer bluebarb daily-planner; do
  cp ~/.config/opencode/agents/${f}.md.bak.$TIMESTAMP ~/.config/opencode/agents/${f}.md
done

# Restart services
~/Models/llama-server-personal.sh restart-dedicated
sleep 5
~/Models/llama-server-personal.sh restart-proxycache

# Router and new models remain available for continued testing
```

---

## Post-Upgrade Testing

### Smoke Tests (immediate, Phase 6)

All smoke tests are included in Phase 6 above. They verify:
- All 5 services running
- Dedicated server responds with `qwen3.8-27b`
- Router lists all 7 models
- Each new model returns coherent responses
- Proxycache end-to-end works
- OpenCode integration works

### Benchmarks (evaluation period, days 1-3)

**Benchmark A: Model speed comparison**
```bash
STANDARD_PROMPT='{"messages":[{"role":"user","content":"Write a Python implementation of merge sort with type hints and docstrings."}],"max_tokens":512}'

for model in qwen3.8-27b qwen3.6-27b qwen3.6-moe gemma-4-31b gemma-4-26b-moe muse-glimmer-30b nemotron-3.5-lightning; do
  echo "=== $model ==="
  START=$(date +%s%N)
  curl -s http://127.0.0.1:18082/v1/chat/completions \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"$model\",\"messages\":[{\"role\":\"user\",\"content\":\"Write a Python implementation of merge sort with type hints and docstrings.\"}],\"max_tokens\":512}" > /dev/null
  END=$(date +%s%N)
  ELAPSED=$(( (END - START) / 1000000 ))
  echo "Total time: ${ELAPSED}ms"
  sleep 5  # Let router unload before next model
done
```

**Benchmark B: Qwen3.8 vs Qwen3.6 quality comparison**
Run the same set of 5-10 coding tasks through both models (dedicated for 3.8, router for 3.6) and compare output quality, speed, and token usage.

### Thinking Preservation Experiment

**Hypothesis:** With `preserve_thinking:false` removed, Qwen3.8 will produce thinking content that OpenCode now properly counts in its context budget.

**Test:**
```bash
# Test with a reasoning-heavy prompt
curl -s http://127.0.0.1:18080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Design a caching strategy for a multi-tenant SaaS platform. Consider eviction policies, TTL, and consistency."}],"max_tokens":1024}' \
  | python3 -c "
import sys, json
r = json.loads(sys.stdin.read())
content = r['choices'][0]['message']['content']
usage = r.get('usage', {})
print(f'Total tokens: {usage.get(\"total_tokens\", \"?\")}')
print(f'Prompt tokens: {usage.get(\"prompt_tokens\", \"?\")}')
print(f'Completion tokens: {usage.get(\"completion_tokens\", \"?\")}')
print()
# Check for thinking tags
if '<think' in content or '<thinking' in content or 'thinking' in content[:200].lower():
    print('Thinking content detected: YES')
else:
    print('Thinking content detected: NO (may be inline reasoning)')
print()
print(content[:500])
"
```

**Success criteria:**
- Thinking content is present in responses
- OpenCode doesn't report context overflow errors
- Answer quality is comparable or better than Qwen3.6

### reasoning_effort Experiment

If OpenCode supports `reasoning_effort` as a parameter, test each level:

```bash
for effort in none low medium high xhigh; do
  echo "=== reasoning_effort=$effort ==="
  START=$(date +%s%N)
  curl -s http://127.0.0.1:18080/v1/chat/completions \
    -H "Content-Type: application/json" \
    -d "{
      \"model\": \"qwen3.8-27b\",
      \"messages\": [{\"role\": \"user\", \"content\": \"Design a rate limiting system for an API gateway.\"}],
      \"max_tokens\": 512
    }" | python3 -c "
import sys, json
r = json.loads(sys.stdin.read())
usage = r.get('usage', {})
print(f'Tokens: {usage.get(\"total_tokens\", \"?\")}, Output: {usage.get(\"completion_tokens\", \"?\")}')
"
  END=$(date +%s%N)
  ELAPSED=$(( (END - START) / 1000000 ))
  echo "Time: ${ELAPSED}ms"
  echo
done
```

---

## Complete File Change Summary

| File | Action | Changes |
|------|--------|---------|
| `~/Models/models-personal.ini` | **Modify** | Add 3 new model sections (qwen3.8-27b, muse-glimmer-30b, nemotron-3.5-lightning); keep existing 4 |
| `~/Models/llama-server-personal.sh` | **Modify** | `DEDICATED_MODEL` path, `--alias`, remove `preserve_thinking:false` from both dedicated and router, retain `--spec-type draft-mtp` |
| `~/Models/proxycache/env.sh` | **Modify** | `MODEL_ID` → `qwen3.8-27b` |
| `~/.config/opencode/opencode.json` | **Modify** | Default model, dedicated provider model key, router new entries |
| `~/.config/opencode/agents/assistant.md` | **Modify** | model → qwen3.8-27b |
| `~/.config/opencode/agents/orchestrator.md` | **Modify** | model → qwen3.8-27b |
| `~/.config/opencode/agents/design.md` | **Modify** | model → qwen3.8-27b |
| `~/.config/opencode/agents/critic.md` | **Modify** | model → qwen3.8-27b |
| `~/.config/opencode/agents/plan-impl.md` | **Modify** | model → qwen3.8-27b |
| `~/.config/opencode/agents/implement.md` | **Modify** | model → qwen3.8-27b |
| `~/.config/opencode/agents/synthesizer.md` | **Modify** | model → qwen3.8-27b |
| `~/.config/opencode/agents/bluebarb.md` | **Modify** | model → qwen3.8-27b |
| `~/.config/opencode/agents/daily-planner.md` | **Modify** | model → qwen3.8-27b |
| `~/.config/opencode/agents/design-gemma.md` | **No change** | Router agent, unchanged |
| `~/.config/opencode/agents/critic-gemma.md` | **No change** | Router agent, unchanged |
| `~/.config/opencode/agents/plan-impl-gemma.md` | **No change** | Router agent, unchanged |

**New directories created:**
- `~/Models/Qwen3.8-27B-GGUF/` (~28 GB)
- `~/Models/Muse-Glimmer-30B-GGUF/` (~31 GB)
- `~/Models/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-GGUF/` (~32 GB)

**Backup files created (Pre-Flight):**
- `~/Models/models-personal.ini.bak.$TIMESTAMP`
- `~/Models/llama-server-personal.sh.bak.$TIMESTAMP`
- `~/Models/proxycache/env.sh.bak.$TIMESTAMP`
- `~/.config/opencode/opencode.json.bak.$TIMESTAMP`
- `~/.config/opencode/agents/*.md.bak.$TIMESTAMP` (12 files)

---

## New Model Feature Summary

| Feature | Qwen3.8-27B | Muse Glimmer-30B | Nemotron 3.5 Lightning |
|---------|-------------|------------------|----------------------|
| Architecture | Dense 27B | Dense 30B | MoE 30B/3B active |
| MTP | Built-in (no separate file) | None | Built-in (no separate file) |
| Vision | Yes (mmproj-F16.gguf) | Yes (mmproj Q8_0) | No (text-only) |
| Thinking | `reasoning_effort` param | System prompt control | `enable_thinking` kwarg |
| Context | 262K native | 131K | 1M native (131K configured) |
| Sampling | temp=0.6, top-p=0.95, top-k=20 | temp=0.6, top-p=0.95, top-k=20 | temp=0.6, top-p=0.95, top-k=20 |
| Best for | General-purpose, agentic | Creative reasoning, multimodal | Fast MoE, long context |
| Router alias | `qwen3.8-27b` | `muse-glimmer-30b` | `nemotron-3.5-lightning` |
| HF repo | `unsloth/Qwen3.8-27B-GGUF` | `unsloth/Muse-Glimmer-30B-GGUF` | `unsloth/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-GGUF` |

---

## Remaining Tradeoffs

1. **Nemotron context limited to 131K:** Nemotron has 1M native context, but we configure it at 131K to avoid KV cache bloat on the router (1M context at q8_0 would consume ~120 GB of KV cache). If long-context tasks are needed, Nemotron could be given a larger context in a future config update, or run as a standalone server.

2. **Muse Glimmer without speculative decoding:** The DFlash drafter exists in the Unsloth repo but is not configured. This means Muse Glimmer won't benefit from speculative decoding speedups. It can be added later if benchmarks show it helps. The tradeoff is simplicity and reliability now vs. potential speedup later.

3. **No `presence_penalty` on Qwen3.8:** Unsloth guidance suggests `presence_penalty = 1.5` for Qwen3.8, but this is a significant behavioral change not tested locally. It's deferred to the evaluation period where it can be added incrementally if repetition issues arise.

4. **All agents on dedicated Qwen3.8:** Rather than "dynamic tiering" (routing different agents to different models), all agents use the dedicated Qwen3.8. This simplifies debugging and ensures consistent warm-cache performance. Dynamic tiering can be explored later as a separate optimization.

5. **Qwen3.6-27B kept on router:** The old model is retained for comparison during the evaluation period. This adds ~27 GB to the router's model pool (though only one model is loaded at a time due to `models-max=1`). After the evaluation period, it can be removed to free disk space.

6. **Router `preserve_thinking` removed:** Thinking is now enabled on both dedicated and router paths. This means all models accessed through the router will produce thinking content. If any model produces excessive thinking that wastes tokens, the router-specific `--chat-template-kwargs` can be re-added selectively.

7. **Proxycache cold start:** Clearing the slot cache means the proxycache starts with zero hits. The first several conversations will have higher latency as the cache rebuilds. This is a one-time cost after the upgrade.

8. **reasoning_effort not set per-agent:** The `reasoning_effort` parameter is a Qwen3.8 feature that controls how much thinking the model does. It's not set in agent configs because OpenCode's support for this as a frontmatter field is unconfirmed. It can be added during the evaluation period once the supported mechanism is verified.
