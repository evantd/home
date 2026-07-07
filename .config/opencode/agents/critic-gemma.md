---
name: critic-gemma
description: Reviews plans, code, or proposals with gemma-4-31b. Provides alternative critique perspective for diversity.
model: "llama-server/gemma-4-31b"
mode: all
temperature: 0.5
permission:
  edit: allow
  bash: allow
prompt:
  file: ../prompts/critic.md
---
