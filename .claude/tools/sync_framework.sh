#!/usr/bin/env bash
# sync_framework.sh — keep a vault's FRAMEWORK in sync with the published template.
#
# The framework (CLAUDE.md, .claude/, _templates/, docs/, .obsidian/, README, …)
# is developed in the open at TEMPLATE_REPO. A vault is a private instance of it.
# This tool moves framework files between the two, and nothing else:
#
#   - it NEVER touches vault content (inbox/, wiki/, _attachments/),
#   - it NEVER commits or pushes — every change lands uncommitted, for a human
#     to review and commit,
#   - it REFUSES to overwrite files carrying uncommitted local edits — commit
#     or stash them first, so nothing of yours can ever be lost, and
#   - export ships ONLY files the template already tracks: anything else found
#     in a framework directory (a personal skill, plugin data, a misfiled note)
#     is skipped and listed; opt genuinely new framework files in with --add.
#
# Usage (run from inside your vault):
#   sync_framework.sh update              copy the latest published framework into this vault
#   sync_framework.sh diff                show how this vault's framework differs from published
#   sync_framework.sh export <checkout>   copy this vault's framework into a local clone of the
#                                         template (review it there, commit, open a PR)
#   sync_framework.sh <mode> --repo URL   use a different template repo (e.g. your fork)
#   sync_framework.sh export <checkout> --add <path>   include a NEW file or dir in the export
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
ADD_PATHS=()
case "$MODE" in
  update|diff) ;;
  export) DEST="${1:?export needs the path to a template checkout}"; shift ;;
  *) sed -n '2,23p' "$0"; exit 2 ;;
esac
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) TEMPLATE_REPO="${2:?--repo needs a URL}"; shift 2 ;;
    --add)  ADD_PATHS+=("${2:?--add needs a path}"); shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

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

# The template's git index is the allowlist: a file it does not track is
# personal (your own skill, plugin data, a misfiled note) until said otherwise
# with --add. This is what keeps a blind directory copy from leaking.
tracked=$(git -C "$DEST" ls-files)

is_tracked() { printf '%s\n' "$tracked" | grep -qxF "$1"; }

is_added() {
  local f="$1" p
  for p in ${ADD_PATHS[@]+"${ADD_PATHS[@]}"}; do
    p="${p%/}"; p="${p#./}"
    [ "$f" = "$p" ] && return 0
    case "$f" in "$p"/*) return 0 ;; esac
  done
  return 1
}

copied=0; skipped=""
for root in "${FRAMEWORK_PATHS[@]}"; do
  [ -e "$root" ] || continue
  while IFS= read -r f; do
    if ! is_tracked "$f" && ! is_added "$f"; then
      skipped="$skipped$f"$'\n'
      continue
    fi
    if [ ! -f "$DEST/$f" ] || ! cmp -s "$f" "$DEST/$f"; then
      mkdir -p "$DEST/$(dirname "$f")"
      cp "$f" "$DEST/$f"
      echo "  -> $f"
      copied=$((copied+1))
    fi
  done < <(find "$root" -type f 2>/dev/null | sed 's|^\./||' | grep -vE "$LOCAL_FILES")
done

if [ -n "$skipped" ]; then
  echo
  echo "Skipped — the template does not track these, so they stay home:"
  printf '%s' "$skipped" | sed 's/^/  ? /'
  echo "A genuinely new framework file? Re-run adding: --add <path>"
fi

if [ "$copied" -eq 0 ]; then
  echo "Nothing to export — the checkout already matches this vault's framework."
else
  echo
  echo "Exported $copied file(s) to $DEST — review with git status there, commit, and open a PR."
fi
