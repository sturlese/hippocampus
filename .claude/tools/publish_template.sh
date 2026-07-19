#!/usr/bin/env bash
# publish_template.sh — publish the vault's FRAMEWORK (never its content) as a
# public GitHub template repo.
#
# How it works — the two repos share NO git history; the bridge is a plain
# file copy into a fresh repo:
#   1. Export the vault's root (scaffold) commit via `git archive`: pristine
#      wiki seeds (index/log/hot), empty inbox, no history.
#   2. Overlay the CURRENT framework files (CLAUDE.md, README, .claude/,
#      .obsidian/, _templates/, .gitignore) so improvements ship too.
#   3. Strip local state, verify no personal content slipped in.
#   4. git init + single commit; push (force) to the public repo.
#
# The public repo therefore always contains exactly one commit with the
# latest framework. Personal roots (inbox/, wiki/ content, _attachments/)
# only ever come from the pristine scaffold commit.
#
# Usage:
#   publish_template.sh              dry run: build + list what would ship
#   publish_template.sh --push       create or update the public repo (needs gh)
#   publish_template.sh --repo NAME  override repo name (default: hippocampus)
set -euo pipefail

VAULT="$(cd "$(dirname "$0")/../.." && pwd)"
REPO_NAME="hippocampus"
PUSH=0

while [ $# -gt 0 ]; do
  case "$1" in
    --push) PUSH=1 ;;
    --repo) REPO_NAME="${2:?--repo needs a name}"; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done

# Copied from the current working tree — must never contain personal data.
FRAMEWORK_PATHS=(CLAUDE.md README.md LICENSE .gitignore .claude .obsidian _templates assets docs)
# Only ever taken from the scaffold commit; real content here must abort the publish.
PERSONAL_ROOTS=(inbox wiki _attachments)
SEED_FILES="wiki/index.md wiki/log.md wiki/hot.md"

cd "$VAULT"
[ -d .git ] || { echo "fatal: $VAULT is not a git repository" >&2; exit 1; }

SCAFFOLD=$(git rev-list --max-parents=0 HEAD | tail -1)
echo "vault:    $VAULT"
echo "scaffold: $(git log --oneline --no-decorate -1 "$SCAFFOLD")"
echo "repo:     $REPO_NAME"
echo

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
EXPORT="$TMP/export"
mkdir -p "$EXPORT"

# 1. Pristine snapshot of the scaffold commit (files only, no history)
git archive "$SCAFFOLD" | tar -x -C "$EXPORT"

# 2. Overlay current framework files
for p in "${FRAMEWORK_PATHS[@]}"; do
  rm -rf "${EXPORT:?}/$p"
  [ -e "$VAULT/$p" ] && cp -R "$VAULT/$p" "$EXPORT/$p"
done

# 3. Strip local/private state that must not ship
rm -f "$EXPORT/.claude/settings.local.json" \
      "$EXPORT/.obsidian/workspace.json" \
      "$EXPORT/.obsidian/workspace-mobile.json"
find "$EXPORT" -name '.DS_Store' -delete 2>/dev/null || true

# 4. Safety net: personal roots may contain only .gitkeep files and the wiki seeds
violations=""
for root in "${PERSONAL_ROOTS[@]}"; do
  [ -d "$EXPORT/$root" ] || continue
  while IFS= read -r f; do
    rel="${f#"$EXPORT/"}"
    case " $SEED_FILES " in *" $rel "*) continue ;; esac
    violations="$violations$rel"$'\n'
  done < <(find "$EXPORT/$root" -type f ! -name '.gitkeep')
done
if [ -n "$violations" ]; then
  echo "fatal: unexpected files in personal roots — refusing to publish:" >&2
  printf '%s' "$violations" | sed 's/^/  /' >&2
  exit 1
fi

# 5. Fresh single-commit history
cd "$EXPORT"
git init -q
git checkout -qb main
git add -A
git commit -qm "Hippocampus template — synced from vault $(date +%Y-%m-%d)"

echo "Files that would be published ($(git ls-files | wc -l | tr -d ' ')):"
git ls-files | sed 's/^/  /'
echo

if [ "$PUSH" -eq 0 ]; then
  echo "Dry run — nothing pushed. Review the list above, then re-run with --push."
  exit 0
fi

command -v gh >/dev/null 2>&1 || { echo "fatal: --push requires the gh CLI (brew install gh; gh auth login)" >&2; exit 1; }

if gh repo view "$REPO_NAME" >/dev/null 2>&1; then
  proto=$(gh config get -h github.com git_protocol 2>/dev/null || echo https)
  if [ "$proto" = "ssh" ]; then
    remote=$(gh repo view "$REPO_NAME" --json sshUrl -q .sshUrl)
  else
    remote="$(gh repo view "$REPO_NAME" --json url -q .url).git"
  fi
  git remote add origin "$remote"
  git push -q --force origin main || {
    echo "fatal: push failed. If it was an auth error, run: gh auth setup-git (https) or check your SSH keys" >&2
    exit 1
  }
  echo "updated: $(gh repo view "$REPO_NAME" --json url -q .url)"
else
  gh repo create "$REPO_NAME" --public --source . --push
  echo "created: $(gh repo view "$REPO_NAME" --json url -q .url)"
fi
full_name=$(gh repo view "$REPO_NAME" --json nameWithOwner -q .nameWithOwner)
gh repo edit "$full_name" --template=true >/dev/null 2>&1 \
  || echo "note: mark it as a template manually: GitHub → Settings → Template repository"
