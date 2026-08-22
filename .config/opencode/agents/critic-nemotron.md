---
name: critic-nemotron
description: Reviews plans, code, or proposals with nemotron-moe. Provides alternative critique perspective for diversity.
model: "llama-server/nemotron-moe"
mode: all
temperature: 0.5
permission:
  edit: allow
  bash: allow
prompt:
  file: ../prompts/critic.md
---
