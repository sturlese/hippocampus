#!/usr/bin/env bash
# sync_framework.sh — keep a vault's FRAMEWORK in sync with the published template.
#
# The framework (CLAUDE.md, .claude/, _templates/, docs/, .obsidian/, README, …)
# is developed in the open at TEMPLATE_REPO. A vault is a private instance of it.
# This tool moves framework files between the two, and nothing else:
#
#   - it NEVER touches vault content (inbox/, wiki/, _attachments/),
#   - it NEVER commits or pushes — every change lands uncommitted, for a human
#     to review and commit, and
#   - it REFUSES to overwrite files carrying uncommitted local edits — commit
#     or stash them first, so nothing of yours can ever be lost.
#
# Usage (run from inside your vault):
#   sync_framework.sh update              copy the latest published framework into this vault
#   sync_framework.sh diff                show how this vault's framework differs from published
#   sync_framework.sh export <checkout>   copy this vault's framework into a local clone of the
#                                         template (review it there, commit, open a PR)
#   sync_framework.sh <mode> --repo URL   use a different template repo (e.g. your fork)
set -euo pipefail

TEMPLATE_REPO="https://github.com/sturlese/hippocampus"

# Content roots — owned by the vault, never shipped by the framework.
PERSONAL_ROOTS='^(wiki|inbox|_attachments)/'
# Framework roots — what `export` copies out of a vault.
FRAMEWORK_PATHS=(CLAUDE.md README.md LICENSE .gitignore .claude .obsidian _templates assets docs)
# Machine-local files that must never travel in either direction.
LOCAL_FILES='(^|/)(\.DS_Store|hook-errors\.log|settings\.local\.json|template\.local|workspace(-mobile)?\.json)$'

MODE="${1:-}"; shift || true
DEST=""
case "$MODE" in
  update|diff) ;;
  export) DEST="${1:?export needs the path to a template checkout}"; shift ;;
  *) sed -n '2,19p' "$0"; exit 2 ;;
esac
[ "${1:-}" = "--repo" ] && TEMPLATE_REPO="${2:?--repo needs a URL}"

[ -d .git ] || { echo "fatal: run this from the root of your vault (a git repository)" >&2; exit 1; }
if [ -f .claude/template.local ]; then
  echo "fatal: this is a template checkout, not a vault (.claude/template.local present)." >&2
  echo "Edit the framework here directly; run update/export from a vault." >&2
  exit 1
fi

# ---------------------------------------------------------------- update / diff
if [ "$MODE" = "update" ] || [ "$MODE" = "diff" ]; then
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
  echo "template: $TEMPLATE_REPO"
  git clone -q --depth 1 "$TEMPLATE_REPO" "$TMP/template"

  # The template's own git index is the authoritative framework file list.
  changed=""; added=""
  while IFS= read -r f; do
    if [ ! -f "$f" ]; then
      added="$added$f"$'\n'
    elif ! cmp -s "$TMP/template/$f" "$f"; then
      changed="$changed$f"$'\n'
    fi
  done < <(git -C "$TMP/template" ls-files | grep -vE "$PERSONAL_ROOTS" | grep -vE "$LOCAL_FILES")

  if [ -z "$added$changed" ]; then
    echo "Framework is up to date with the published template."
    exit 0
  fi
  [ -n "$added" ]   && { echo "New in template:";   printf '%s' "$added"   | sed 's/^/  + /'; }
  [ -n "$changed" ] && { echo "Differs from template:"; printf '%s' "$changed" | sed 's/^/  ~ /'; }

  # Files that differ from the template AND carry uncommitted local edits would
  # be unrecoverable if overwritten (nothing auto-commits framework files).
  dirty=""
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if [ -n "$(git status --porcelain -- "$f" 2>/dev/null)" ]; then
      dirty="$dirty$f"$'\n'
    fi
  done < <(printf '%s' "$changed")

  if [ "$MODE" = "diff" ]; then
    if [ -n "$dirty" ]; then
      echo
      echo "Note: these carry uncommitted local edits — update will refuse to touch them:"
      printf '%s' "$dirty" | sed 's/^/  ! /'
    fi
    echo
    echo "Diff only — nothing written. Local edits meant for the template? export them first:"
    echo "  $0 export <template-checkout>"
    exit 0
  fi

  if [ -n "$dirty" ]; then
    echo >&2
    echo "fatal: refusing to overwrite files with uncommitted local edits:" >&2
    printf '%s' "$dirty" | sed 's/^/  ! /' >&2
    echo "Commit or stash them, then re-run. Meant for the template? export them instead:" >&2
    echo "  $0 export <template-checkout>" >&2
    exit 1
  fi

  printf '%s%s' "$added" "$changed" | while IFS= read -r f; do
    [ -n "$f" ] || continue
    mkdir -p "$(dirname "$f")"
    cp "$TMP/template/$f" "$f"
  done
  echo
  echo "Updated. Review with git status / git diff, then commit in this vault."
  exit 0
fi

# ------------------------------------------------------------------------ export
[ -d "$DEST/.git" ] || { echo "fatal: $DEST is not a git checkout of the template" >&2; exit 1; }
[ -f "$DEST/CLAUDE.md" ] || { echo "fatal: $DEST does not look like the template (no CLAUDE.md)" >&2; exit 1; }

copied=0
for root in "${FRAMEWORK_PATHS[@]}"; do
  [ -e "$root" ] || continue
  while IFS= read -r f; do
    if [ ! -f "$DEST/$f" ] || ! cmp -s "$f" "$DEST/$f"; then
      mkdir -p "$DEST/$(dirname "$f")"
      cp "$f" "$DEST/$f"
      echo "  -> $f"
      copied=$((copied+1))
    fi
  done < <(find "$root" -type f 2>/dev/null | sed 's|^\./||' | grep -vE "$LOCAL_FILES")
done

if [ "$copied" -eq 0 ]; then
  echo "Nothing to export — the checkout already matches this vault's framework."
else
  echo
  echo "Exported $copied file(s) to $DEST — review with git status there, commit, and open a PR."
fi
