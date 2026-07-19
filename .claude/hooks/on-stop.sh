#!/usr/bin/env bash
# Stop hook: (1) if wiki content changed after the last hot.md refresh, ask Claude
# to update the hot cache before stopping; (2) once hot.md is fresh, auto-commit
# the vault. Loop-safe via the stop_hook_active flag Claude Code sets when a stop
# was already blocked once.
set -u
input=$(cat 2>/dev/null || true)

cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0
[ -d wiki ] || exit 0
# Template checkouts are not vaults: no hot-cache enforcement, no auto-commit.
# The marker is untracked (see .gitignore) — create it only in a template clone.
[ -f .claude/template.local ] && exit 0

stop_active=0
printf '%s' "$input" | grep -q '"stop_hook_active"[[:space:]]*:[[:space:]]*true' && stop_active=1

if [ "$stop_active" -eq 0 ] && [ -f wiki/hot.md ]; then
  changed=$(find wiki -name '*.md' ! -name 'hot.md' -newer wiki/hot.md 2>/dev/null | head -1)
  if [ -n "$changed" ]; then
    printf '{"decision":"block","reason":"Wiki pages changed this session but wiki/hot.md was not refreshed. Overwrite wiki/hot.md now (<=500 words; sections: Last Updated, Key Recent Facts, Recent Changes, Active Threads; bump the updated: field). Then stop."}\n'
    exit 0
  fi
fi

if [ -d .git ]; then
  ERRLOG=".claude/hooks/hook-errors.log"
  git add -A -- inbox wiki _templates _attachments CLAUDE.md README.md 2>>"$ERRLOG"
  if ! git diff --cached --quiet 2>/dev/null; then
    if ! git commit -q -m "vault: auto-commit $(date '+%Y-%m-%d %H:%M')" 2>>"$ERRLOG"; then
      printf '%s auto-commit FAILED — vault changes are staged but NOT committed\n' \
        "$(date '+%Y-%m-%dT%H:%M:%S')" >> "$ERRLOG"
    fi
  fi
fi
exit 0
