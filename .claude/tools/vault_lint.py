#!/usr/bin/env python3
"""Deterministic health check for a Hippocampus vault.

Scans wiki/**/*.md and reports:
  - frontmatter problems (missing block, missing/invalid required fields,
    invalid calendar dates, list fields that aren't lists, type/folder mismatch)
  - dead wikilinks (targets that resolve to no file)
  - duplicate basenames (they break wikilink resolution)
  - alias collisions (alias vs page title, alias declared twice)
  - orphan pages (no inbound links from any content page)
  - index drift (content pages missing from wiki/index.md)
  - empty sections (headings with no content)
  - oversized hot cache (wiki/hot.md over the word budget)

Usage: vault_lint.py [--vault PATH] [--json]
Exit codes: 0 = scan completed (findings are in the output), 2 = fatal error.
Stdlib only.
"""

import argparse
import json
import re
import sys
from collections import defaultdict
from datetime import datetime
from pathlib import Path

VALID_TYPES = {"source", "entity", "concept", "project", "note", "meta"}
VALID_STATUS = {"seed", "developing", "mature", "evergreen"}
REQUIRED_FIELDS = ["type", "title", "created", "updated", "tags", "status"]
RECOMMENDED_FIELDS = ["related", "sources"]
LIST_FIELDS = ("tags", "related", "sources", "aliases")
FOLDER_TYPES = {"sources": "source", "entities": "entity", "concepts": "concept",
                "projects": "project", "notes": "note", "meta": "meta"}
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")


def valid_date(s):
    """Zero-padded YYYY-MM-DD that is also a real calendar date."""
    if not DATE_RE.match(s):
        return False
    try:
        datetime.strptime(s, "%Y-%m-%d")
        return True
    except ValueError:
        return False
WIKILINK_RE = re.compile(r"!?\[\[([^\[\]]+?)\]\]")
HEADING_RE = re.compile(r"^(#{1,6})\s+\S")
HOT_WORD_BUDGET = 500

# Files exempt from orphan/index checks (hubs and journals, linked by design or not at all)
META_BASENAMES = {"index.md", "log.md", "hot.md"}


def parse_frontmatter(text):
    """Minimal flat-YAML frontmatter parser. Returns (dict, error_string)."""
    if not text.startswith("---"):
        return None, "no frontmatter block"
    lines = text.split("\n")
    end = None
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            end = i
            break
    if end is None:
        return None, "frontmatter block never closed"
    fm, current_key = {}, None
    for raw in lines[1:end]:
        line = raw.rstrip()
        if not line.strip() or line.strip().startswith("#"):
            continue
        item = re.match(r"^\s+-\s*(.*)$", line)
        if item and current_key:
            fm[current_key].append(item.group(1).strip().strip("\"'"))
            continue
        kv = re.match(r"^([A-Za-z_][\w-]*):\s*(.*)$", line)
        if not kv:
            continue  # lenient: skip lines we don't understand
        key, value = kv.group(1), kv.group(2).strip()
        comment = re.search(r"\s+#\s", value)
        if comment and not value.startswith(("\"", "'")):
            value = value[: comment.start()].strip()
        if value == "":
            fm[key], current_key = [], key  # may become a block list
        elif value.startswith("[") and value.endswith("]"):
            inner = value[1:-1].strip()
            fm[key] = [v.strip().strip("\"'") for v in inner.split(",") if v.strip()] if inner else []
            current_key = None
        else:
            fm[key], current_key = value.strip("\"'"), None
    return fm, None


def link_targets(text):
    """All wikilink targets in the text, normalized (alias/heading/block refs stripped)."""
    targets = []
    for m in WIKILINK_RE.finditer(text):
        t = m.group(1).split("|")[0].split("#")[0].strip()
        if t:
            targets.append(t)
    return targets


def body_of(text):
    if text.startswith("---"):
        parts = text.split("\n")
        for i in range(1, len(parts)):
            if parts[i].strip() == "---":
                return "\n".join(parts[i + 1:])
    return text


def find_empty_sections(text):
    """Headings (level >= 2) with no content before the next heading or EOF."""
    lines = body_of(text).split("\n")
    empty, current, has_content = [], None, True
    for line in lines:
        if HEADING_RE.match(line):
            if current is not None and not has_content:
                empty.append(current)
            level = len(line) - len(line.lstrip("#"))
            current = line.strip() if level >= 2 else None
            has_content = current is None
        elif line.strip():
            has_content = True
    if current is not None and not has_content:
        empty.append(current)
    return empty


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--vault", default=".", help="vault root (default: cwd)")
    ap.add_argument("--json", action="store_true", help="machine-readable output")
    args = ap.parse_args()

    root = Path(args.vault).resolve()
    wiki = root / "wiki"
    if not wiki.is_dir():
        print(f"fatal: {wiki} is not a directory", file=sys.stderr)
        return 2

    pages = sorted(p for p in wiki.rglob("*.md") if not p.name.startswith("."))
    findings = []

    def add(severity, check, path, message):
        findings.append({
            "severity": severity, "check": check,
            "file": str(path.relative_to(root)) if isinstance(path, Path) else path,
            "message": message,
        })

    # Resolution map: basename (no extension) -> paths, for wikilink resolution
    by_name = defaultdict(list)
    for p in pages:
        by_name[p.stem].append(p)
    attachments = {p.name for p in (root / "_attachments").rglob("*") if p.is_file()} \
        if (root / "_attachments").is_dir() else set()

    texts = {p: p.read_text(encoding="utf-8", errors="replace") for p in pages}
    is_meta = {p: (p.name in META_BASENAMES or p.parent.name == "meta") for p in pages}

    # --- duplicate basenames (case-insensitive: macOS + Obsidian resolution) ---
    lower_names = defaultdict(list)
    for p in pages:
        lower_names[p.stem.lower()].append(p)
    for name, paths in sorted(lower_names.items()):
        if len(paths) > 1:
            listed = ", ".join(str(q.relative_to(root)) for q in paths)
            add("error", "duplicates", paths[0], f"duplicate basename breaks wikilinks: {listed}")

    # --- per-page checks ---
    inbound = defaultdict(set)  # page path -> set of linking pages (content pages only)
    page_aliases = []           # (page path, alias) pairs for collision checks
    for p in pages:
        text = texts[p]
        fm, err = parse_frontmatter(text)
        if err:
            add("error", "frontmatter", p, err)
            fm = {}
        else:
            for field in REQUIRED_FIELDS:
                if field not in fm or fm[field] in ("", []):
                    add("error", "frontmatter", p, f"missing required field: {field}")
            for field in RECOMMENDED_FIELDS:
                if field not in fm:
                    add("warn", "frontmatter", p, f"missing recommended field: {field}")
            if fm.get("type") and fm["type"] not in VALID_TYPES:
                add("error", "frontmatter", p, f"invalid type: {fm['type']!r}")
            if fm.get("status") and fm["status"] not in VALID_STATUS:
                add("error", "frontmatter", p, f"invalid status: {fm['status']!r}")
            rel = p.relative_to(wiki).parts
            expected = FOLDER_TYPES.get(rel[0]) if len(rel) > 1 else "meta"
            if expected and fm.get("type") and fm["type"] in VALID_TYPES and fm["type"] != expected:
                add("error", "frontmatter", p,
                    f"type {fm['type']!r} but this folder expects {expected!r}")
            for field in LIST_FIELDS:
                if field in fm and not isinstance(fm[field], list):
                    add("error", "frontmatter", p, f"{field} must be a list, got: {fm[field]!r}")
            for field in ("created", "updated"):
                v = fm.get(field)
                if isinstance(v, str) and v and not valid_date(v):
                    add("error", "frontmatter", p, f"{field} is not a valid YYYY-MM-DD date: {v!r}")
            if isinstance(fm.get("aliases"), list):
                for alias in fm["aliases"]:
                    if isinstance(alias, str) and alias and alias.lower() != p.stem.lower():
                        page_aliases.append((p, alias))

        for section in find_empty_sections(text):
            add("warn", "empty_sections", p, f"empty section: {section!r}")

        # --- wikilink resolution ---
        for target in link_targets(text):
            if "." in Path(target).name and not target.endswith(".md"):
                if Path(target).name not in attachments:
                    add("error", "dead_links", p, f"embed target not found: [[{target}]]")
                continue
            stem = Path(target).stem
            resolved = by_name.get(stem, [])
            if not resolved:
                check = "index_drift" if p.name == "index.md" else "dead_links"
                add("error", check, p, f"dead link: [[{target}]]")
            elif not is_meta[p]:
                for q in resolved:
                    inbound[q].add(p)

    # --- alias collisions ---
    seen_alias = {}
    for p, alias in page_aliases:
        al = alias.lower()
        others = [q for q in lower_names.get(al, []) if q != p]
        if others:
            add("error", "aliases", p,
                f"alias {alias!r} collides with page {others[0].relative_to(root)}")
        if al in seen_alias and seen_alias[al] != p:
            add("error", "aliases", p,
                f"alias {alias!r} already declared by {seen_alias[al].relative_to(root)}")
        else:
            seen_alias.setdefault(al, p)

    # --- orphans and index drift ---
    index_text = texts.get(wiki / "index.md", "")
    index_stems = {Path(t).stem for t in link_targets(index_text)}
    for p in pages:
        if is_meta[p] or p.name == "_index.md":
            continue
        if not inbound.get(p):
            add("warn", "orphans", p, "no inbound links from any content page")
        if p.stem not in index_stems:
            add("warn", "index_drift", p, "not listed in wiki/index.md")

    # --- hot cache size ---
    hot = wiki / "hot.md"
    if hot in texts:
        words = len(body_of(texts[hot]).split())
        if words > HOT_WORD_BUDGET:
            add("warn", "hot_size", hot, f"hot.md is {words} words (budget {HOT_WORD_BUDGET}); trim it")

    # --- report ---
    order = {"error": 0, "warn": 1, "info": 2}
    findings.sort(key=lambda f: (order[f["severity"]], f["check"], f["file"]))
    summary = {
        "pages_scanned": len(pages),
        "errors": sum(1 for f in findings if f["severity"] == "error"),
        "warnings": sum(1 for f in findings if f["severity"] == "warn"),
    }
    if args.json:
        print(json.dumps({"summary": summary, "findings": findings}, indent=2, ensure_ascii=False))
    else:
        print(f"Scanned {summary['pages_scanned']} pages: "
              f"{summary['errors']} errors, {summary['warnings']} warnings\n")
        for f in findings:
            print(f"[{f['severity'].upper():5}] {f['check']:14} {f['file']}: {f['message']}")
        if not findings:
            print("Vault is clean.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
