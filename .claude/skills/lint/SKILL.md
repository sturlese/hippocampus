---
name: lint
description: >
  Health check for the vault: runs the deterministic linter (frontmatter, dead links,
  orphans, duplicates, index drift) plus editorial checks (stale claims, unlinked
  mentions, missing pages), then fixes what the user approves. Triggers on: "lint",
  "revisa el vault", "health check", "chequea el wiki", "limpia el vault", "wiki audit".
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(python3 .claude/tools/vault_lint.py:*)
---

# lint: vault health check

Two passes: the Python tool finds the mechanical problems for free; you add the judgment calls. Then propose fixes — apply only what the user approves.

## 1. Mechanical pass

```bash
python3 .claude/tools/vault_lint.py --json
```

Covers: frontmatter validity, dead wikilinks, broken embeds, duplicate basenames, orphan pages, pages missing from the index, dead index entries, empty sections, hot-cache size. Trust its output; don't re-derive these by reading pages.

## 2. Editorial pass (only what the tool can't see)

Scale to vault size — sample recent pages if the vault is large:

- **Unlinked mentions**: entity/concept names that appear as plain text where a `[[wikilink]]` should be. Grep for the titles of existing pages across `wiki/`.
- **Missing pages**: a concept/entity mentioned across 3+ pages without a page of its own → suggest creating one.
- **Stale claims**: pages whose claims newer pages contradict, without a contradiction callout.
- **Aging seeds**: `status: seed` pages untouched for 30+ days — develop, merge, or delete.

## 3. Report and fix

Present findings grouped by severity, each with a one-line suggested fix. If the user wants a record (or there are many findings), write it to `wiki/meta/lint-report-YYYY-MM-DD.md` (`type: meta`).

Then ask what to fix. Guidance:

- **Safe once approved in bulk**: adding missing frontmatter fields, fixing date formats, adding wikilinks for unlinked mentions, adding missing index entries, removing dead index entries.
- **One-by-one approval**: deleting orphans (isolation may be intentional), merging duplicates, resolving contradictions (needs the user's judgment on which side is true).

After fixing, re-run the tool to confirm, prepend a `lint` entry to `wiki/log.md`, and refresh `wiki/hot.md` if pages changed.
