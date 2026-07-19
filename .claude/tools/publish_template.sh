#!/usr/bin/env bash
# publish_template.sh — publish the vault's FRAMEWORK (never its content) as a
# public GitHub template repo.
#
# How it works — the two repos share NO git history; the bridge is a plain
# file copy:
#   1. Export the vault's root (scaffold) commit via `git archive`: pristine
#      wiki seeds (index/log/hot), empty inbox, no history.
#   2. Overlay the CURRENT framework files (CLAUDE.md, README, .claude/,
#      .obsidian/, _templates/, docs/, assets/, .gitignore) so improvements ship.
#   3. Strip local state, verify no personal content slipped in.
#   4. Clone the published repo, replace its content with the export, and
#      commit ON TOP of its existing history. First run creates the repo.
#
# The public repo therefore accumulates one commit per publish, so consumers
# can see what changed and when. Privacy does NOT come from rewriting history
# — it comes from FRAMEWORK_PATHS below plus the step-4 safety net: personal
# roots (inbox/, wiki/ content, _attachments/) only ever come from the
# pristine scaffold commit, and anything else there aborts the publish.
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

# 5. Without gh there is nothing to diff against — list and stop.
if ! command -v gh >/dev/null 2>&1; then
  [ "$PUSH" -eq 1 ] && { echo "fatal: --push requires the gh CLI (brew install gh; gh auth login)" >&2; exit 1; }
  echo "Files that would be published ($(cd "$EXPORT" && find . -type f | wc -l | tr -d ' ')):"
  (cd "$EXPORT" && find . -type f | sed 's|^\./|  |' | sort)
  echo
  echo "Dry run — nothing pushed. Install gh to diff against the published repo."
  exit 0
fi

# 6. First publish: create the repo from the export.
if ! gh repo view "$REPO_NAME" >/dev/null 2>&1; then
  echo "Files that would be published ($(cd "$EXPORT" && find . -type f | wc -l | tr -d ' ')):"
  (cd "$EXPORT" && find . -type f | sed 's|^\./|  |' | sort)
  echo
  if [ "$PUSH" -eq 0 ]; then
    echo "Dry run — nothing pushed. '$REPO_NAME' does not exist yet; --push would create it."
    exit 0
  fi
  cd "$EXPORT"
  git init -q
  git checkout -qb main
  git add -A
  git commit -qm "Hippocampus template — initial publish"
  gh repo create "$REPO_NAME" --public --source . --push
  echo "created: $(gh repo view "$REPO_NAME" --json url -q .url)"
  full_name=$(gh repo view "$REPO_NAME" --json nameWithOwner -q .nameWithOwner)
  gh repo edit "$full_name" --template=true >/dev/null 2>&1 \
    || echo "note: mark it as a template manually: GitHub → Settings → Template repository"
  exit 0
fi

# 7. Subsequent publishes: commit on top of the published repo's history, so
#    consumers get real diffs instead of a rewritten single commit.
PUBLIC="$TMP/public"
if [ "$(gh config get -h github.com git_protocol 2>/dev/null || echo https)" = "ssh" ]; then
  clone_url=$(gh repo view "$REPO_NAME" --json sshUrl -q .sshUrl)
else
  clone_url="$(gh repo view "$REPO_NAME" --json url -q .url).git"
fi
git clone -q "$clone_url" "$PUBLIC" || {
  echo "fatal: could not clone $clone_url. Auth? Run: gh auth setup-git (https) or check your SSH keys" >&2
  exit 1
}

# Replace the published content wholesale — .git is the only thing kept.
find "$PUBLIC" -mindepth 1 -maxdepth 1 ! -name '.git' -exec rm -rf {} +
(cd "$EXPORT" && tar cf - .) | (cd "$PUBLIC" && tar xf -)

cd "$PUBLIC"
git add -A
if git diff --cached --quiet; then
  echo "Nothing to publish — $REPO_NAME already matches the vault's framework."
  exit 0
fi

echo "Changes to publish ($(git ls-files | wc -l | tr -d ' ') files total):"
git diff --cached --stat | sed 's/^/  /'
echo

if [ "$PUSH" -eq 0 ]; then
  echo "Dry run — nothing pushed. Review the diff above, then re-run with --push."
  exit 0
fi

git commit -qm "Sync framework from vault — $(date +%Y-%m-%d)"
git push -q origin HEAD || {
  echo "fatal: push failed. If it was an auth error, run: gh auth setup-git (https) or check your SSH keys" >&2
  exit 1
}
echo "updated: $(gh repo view "$REPO_NAME" --json url -q .url)"
