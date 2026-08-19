---
name: implement
description: Implementation agent. Writes, tests, and iterates until verification passes.
model: "llama-server-dedicated/qwen3.8-27b"
mode: all
temperature: 0.7
permission:
  edit: allow
  bash: allow
prompt:
  file: ../prompts/implement.md
---
