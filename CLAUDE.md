# Hippocampus — an Obsidian vault managed by Claude Code

This directory is three things at once: a git repository, a Claude Code project, and an Obsidian vault. The user drops messy notes into `inbox/`; Claude turns them into a structured, cross-linked knowledge base under `wiki/`. Obsidian is for browsing (graph view, backlinks); Claude Code is the main interface.

## Layout

```
inbox/          Messy source notes, any format/language. IMMUTABLE: read, never edit.
inbox/_done/    Processed inbox files are MOVED here by the ingest skill (provenance).
wiki/           The structured knowledge base. Everything Claude writes lives here.
├── index.md    Master catalog: one line per page. Update on every page create/rename.
├── log.md      Append-only operations journal. New entries at the TOP. Never edit past entries.
├── hot.md      Recent-context cache, ≤500 words. Overwrite completely each refresh.
├── sources/    One page per ingested source (type: source)
├── concepts/   Ideas, patterns, frameworks (type: concept)
├── entities/   People, orgs, products, tools (type: entity)
├── projects/   Ongoing personal/work projects (type: project)
├── notes/      Synthesis, decisions, saved sessions (type: note)
└── meta/       Lint reports, dashboards (type: meta)
_templates/     Canonical skeletons per note type. THE source of truth for page structure.
_attachments/   Images/PDFs referenced by wiki pages.
docs/           Framework documentation (upstream, part of the template). NOT vault content — never file notes here.
```

## Frontmatter schema

Flat YAML only (no nested objects — Obsidian Properties requires flat). Universal fields, every page:

```yaml
---
type: source | entity | concept | project | note | meta
title: "Human-Readable Title"
created: YYYY-MM-DD
updated: YYYY-MM-DD          # bump on every content edit
tags: [lowercase, hierarchical/ok]
status: seed | developing | mature | evergreen
related: ["[[Other Page]]"]  # wikilinks in YAML must be quoted
sources: ["[[Source Page]]"]
---
```

Type-specific extras are defined in the corresponding `_templates/*.md` skeleton — read the template before creating a page of that type.

## Conventions

- **Language**: wiki pages are written in English, regardless of the source note's language. Keep proper nouns and untranslatable terms as-is.
- **Filenames**: Title Case with spaces (`Compounding Knowledge.md`). Must be unique across the whole vault — wikilinks resolve by bare filename.
- **Wikilinks**: `[[Page Name]]`. Link every mentioned entity/concept that has (or deserves) a page. Aliases: `[[Page|shown text]]`.
- **Folders**: lowercase. New top-level folders under `wiki/` only with the user's OK.
- **Style**: declarative present tense. Write the knowledge, not the conversation ("X works by Y", never "the user asked about X").
- **Page size**: 30–150 lines. If a page outgrows that, split it and cross-link.
- Never modify files in `inbox/` (except moving them to `inbox/_done/` after ingestion). Never rewrite `log.md` history. `hot.md` is a cache, not a journal — overwrite it.

## Answering questions from the vault (read order)

1. Read `wiki/hot.md` — recent context may already answer it.
2. Read `wiki/index.md` — pick the 3–5 relevant pages.
3. Read those pages; follow wikilinks at most one hop further.
4. **Fallback**: if there is still no confident answer, Grep `wiki/` for distinctive terms, aliases and likely synonyms, and read only the strongest matches — the index may not use the question's wording.
5. Synthesize and cite pages: `(Source: [[Page Name]])`.

Never bulk-read the whole vault for a routine question (the Grep fallback searches; it does not mean opening every page). Declare "not in the vault" only after the fallback also fails — then say so explicitly rather than answering from training data, and offer to research + ingest instead.

## Contradictions

When new information conflicts with an existing page, do NOT silently overwrite. Flag both sides with a callout and let the user resolve:

```markdown
> [!warning] Contradiction with [[Other Page]]
> This page claims X; [[Other Page]] claims Y. Needs resolution.
```

## Operations

| User says | What happens |
|---|---|
| "ingest", "procesa el inbox", "procesa esta nota" | `ingest` skill: inbox file(s) → structured wiki pages + index/log/hot updates |
| any question about vault content | read order above, cited answer |
| "lint", "revisa el vault", "health check" | `lint` skill: runs `.claude/tools/vault_lint.py` + editorial checks |
| "guarda esto", "save this", "/save" | `save` skill: files the current conversation as a wiki note |

Hooks (configured in `.claude/settings.json`): `hot.md` is injected at session start; after each turn that changed wiki pages, a Stop hook asks Claude to refresh `hot.md`, then auto-commits the vault content locally (push is manual; commit failures are logged to `.claude/hooks/hook-errors.log`).

## Framework vs. content

The framework — `CLAUDE.md`, `.claude/`, `_templates/`, `docs/`, `README.md`, `.obsidian/` config — is developed in the open at https://github.com/sturlese/hippocampus. Content (`inbox/`, `wiki/`, `_attachments/`) belongs to this vault alone and never leaves it.

If a session edits framework files **in a vault**, remind the user that the change lives in the wrong repo and should be ported: `.claude/tools/sync_framework.sh export <template-checkout>`, then commit and PR there. To bring the latest published framework into a vault: `.claude/tools/sync_framework.sh update`. Neither command ever touches content or commits anything.

## Using this vault from other Claude Code projects

Add to that project's CLAUDE.md:

```markdown
## Personal knowledge base
Path: <absolute path to this vault>
For context not in this project: read wiki/hot.md first, then wiki/index.md,
then only the specific pages you need. Do not use it for general coding questions.
```
