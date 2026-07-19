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
#   3. Strip local state, then run two independent checks (below).
#   4. Clone the published repo, replace its content with the export, and
#      commit ON TOP of its existing history. First run creates the repo.
#
# The public repo accumulates one commit per publish, so consumers can see what
# changed and when. Privacy does NOT come from rewriting history — a published
# leak is public the moment it lands, and force-pushing it away afterwards does
# not un-index it. It comes from two checks that run BEFORE anything is pushed:
#
#   a) Personal roots (inbox/, wiki/ content, _attachments/) only ever come
#      from the pristine scaffold commit; anything else there aborts.
#   b) The published file set must match MANIFEST exactly. Copying whole
#      directories is convenient but blind, so any file the manifest does not
#      declare — anywhere, including docs/ and .claude/ — aborts the publish.
#
# Usage:
#   publish_template.sh              dry run: diff against what is published
#   publish_template.sh --push       create or update the public repo (needs gh)
#   publish_template.sh --accept     record the current file set in MANIFEST
#   publish_template.sh --repo NAME  override repo name (default: hippocampus)
set -euo pipefail

VAULT="$(cd "$(dirname "$0")/../.." && pwd)"
REPO_NAME="hippocampus"
PUSH=0
ACCEPT=0

while [ $# -gt 0 ]; do
  case "$1" in
    --push) PUSH=1 ;;
    --accept) ACCEPT=1 ;;
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
# The authoritative list of every file allowed in the public repo. Anything the
# export contains that is not listed here aborts the publish — copying a whole
# directory is convenient but blind, and this is what makes it safe. Update it
# deliberately with --accept, and review the diff like any other change.
MANIFEST="$VAULT/.claude/tools/published-files.txt"

# Compare the exact set of files about to be published against the manifest.
# Called with the staged file list, so it sees what git would really commit.
check_manifest() {
  local actual expected added removed
  actual=$(printf '%s\n' "$1" | sort)
  expected=""
  [ -f "$MANIFEST" ] && expected=$(grep -vE '^[[:space:]]*(#|$)' "$MANIFEST" | sort)

  added=$(comm -13 <(printf '%s\n' "$expected") <(printf '%s\n' "$actual"))
  removed=$(comm -23 <(printf '%s\n' "$expected") <(printf '%s\n' "$actual"))

  if [ "$ACCEPT" -eq 1 ]; then
    { echo "# Every file allowed in the public template repo."
      echo "# The publisher refuses to ship anything not listed here."
      echo "# Regenerate deliberately: publish_template.sh --accept"
      printf '%s\n' "$actual"
    } > "$MANIFEST"
    echo "Manifest updated ($(printf '%s\n' "$actual" | wc -l | tr -d ' ') files): $MANIFEST"
    [ -n "$added" ] && printf '%s\n' "$added" | sed 's/^/  + /'
    [ -n "$removed" ] && printf '%s\n' "$removed" | sed 's/^/  - /'
    echo
    return 0
  fi

  if [ -n "$added" ]; then
    echo "fatal: these files are not declared in the manifest — refusing to publish:" >&2
    printf '%s\n' "$added" | sed 's/^/  + /' >&2
    echo >&2
    echo "Nothing was published. If they are meant to be public, read them first," >&2
    echo "then run: publish_template.sh --accept" >&2
    echo "Manifest: $MANIFEST" >&2
    exit 1
  fi

  if [ -n "$removed" ]; then
    echo "note: the manifest lists files the export no longer produces:" >&2
    printf '%s\n' "$removed" | sed 's/^/  - /' >&2
    echo "Run --accept to update it." >&2
    echo >&2
  fi
}

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
  check_manifest "$(git ls-files)"
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
check_manifest "$(git ls-files)"
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
