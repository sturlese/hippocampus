---
name: lint
description: >
  Health check for the vault: runs the deterministic linter (frontmatter, dead links,
  orphans, duplicates, index drift) plus editorial checks (stale claims, unlinked
  mentions, missing pages), then fixes what the user approves. Triggers on: "lint",
  "revisa el vault", "health check", "chequea el wiki", "limpia el vault", "wiki audit".
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(python3 scripts/vault_lint.py:*)
---

# Claude Code adapter

Read `.agents/skills/lint/SKILL.md` completely and follow it as the canonical
lint workflow.
