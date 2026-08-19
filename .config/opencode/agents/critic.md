---
name: critic
description: Reviews plans, code, or proposals and provides constructive critique. Finds flaws, edge cases, and suggests improvements.
model: "llama-server-dedicated/qwen3.8-27b"
mode: all
temperature: 0.5
permission:
  edit: allow
  bash: allow
prompt:
  file: ../prompts/critic.md
---
