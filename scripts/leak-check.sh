#!/usr/bin/env bash
# leak-check.sh — tripwire for strings that must never cross a public-surface boundary.
# Usage: scripts/leak-check.sh [commit-ish]    (default HEAD)
# Patterns: built-in IPv4 literals + .git/info/leak-strings.txt (untracked, local only —
# the list itself must never be committed; ERE, one per line, # = comment).
set -euo pipefail
target="${1:-HEAD}"
git rev-parse --verify --quiet "$target^{commit}" >/dev/null || { echo "leak-check: bad target: $target" >&2; exit 2; }
top="$(git rev-parse --show-toplevel)"
list="$top/.git/info/leak-strings.txt"
tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
printf '%s\n' '([0-9]{1,3}\.){3}[0-9]{1,3}' >"$tmp"
if [[ -f "$list" ]]; then
  grep -vE '^[[:space:]]*(#|$)' "$list" >>"$tmp" || true
fi
if git grep -nIE -f "$tmp" "$target" -- . 2>/dev/null | grep .; then
  echo "leak-check: FORBIDDEN STRING in $target — fix before push (built-in IPv4 + .git/info/leak-strings.txt)" >&2
  exit 1
fi
echo "leak-check: clean ($target)"
