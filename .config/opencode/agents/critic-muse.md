---
name: critic-muse
description: Reviews plans, code, or proposals with muse-dense. Provides alternative critique perspective for diversity.
model: "llama-server/muse-dense"
mode: all
temperature: 0.5
permission:
  edit: allow
  bash: allow
prompt:
  file: ../prompts/critic.md
---
