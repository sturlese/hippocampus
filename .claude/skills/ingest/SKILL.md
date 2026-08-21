---
name: ingest
description: >
  Turn messy source notes into structured wiki pages (frontmatter, wikilinks, one folder
  per type) and update the vault's index, log and hot cache. Use when the user drops
  files into inbox/ and asks to process them, points at a note or URL to ingest, or
  pastes raw content to file. Triggers on: "ingest", "ingesta", "procesa el inbox",
  "procesa esta nota", "process this", "add this to the wiki", "mete esto en el brain".
allowed-tools: Read, Write, Edit, Glob, Grep, WebFetch, Bash(mv:*), Bash(shasum:*), Bash(python3 scripts/vault_lint.py:*)
---

# Claude Code adapter

Read `.agents/skills/ingest/SKILL.md` completely and follow it as the canonical
ingest workflow.
