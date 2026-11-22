#!/usr/bin/env bash
# tests/lint.sh :: enforce tab indentation in project sources (vendor/ excluded).
# Indentation is tabs; spaces after the tabs are allowed for alignment. In Markdown,
# fenced blocks without a code language (diagrams, plain text) are exempt.
set -euo pipefail
cd "${ROOT:-$(dirname "$0")/..}"

files=$(git ls-files -co --exclude-standard -- ':!vendor/' ':!legacy/' \
	| grep -E '(\.(c|h|lua|html|css|js|sql|sh|md)|(^|/)Makefile)$')
[ -n "$files" ] || { echo "lint: no files found (not a git checkout?)" >&2; exit 2; }

bad=0
while IFS= read -r f; do
	[ -f "$f" ] || continue
	if out=$(awk -v md="$([[ $f == *.md ]] && echo 1 || echo 0)" '
		BEGIN { langs = " lua c h sh bash html sql css js make makefile " }
		md && /^[ \t]*```/ {
			if (infence) { infence = 0 } else {
				infence = 1; lang = $0; sub(/^[ \t]*```[ \t]*/, "", lang); sub(/[ \t].*/, "", lang)
				exempt = (index(langs, " " tolower(lang) " ") == 0)
			}
			next
		}
		md && infence && exempt { next }
		/^  +[^ ]/ { print FNR ": " $0; n++ }
		END { exit n > 0 }' "$f"); then
		:
	else
		printf '%s\n' "$out" | head -3 | sed "s|^|$f:|"
		bad=$((bad + 1))
	fi
done <<< "$files"

if [ "$bad" -gt 0 ]; then
	echo "lint: $bad file(s) indented with spaces (use tabs)" >&2
	exit 1
fi
# the world's lore (.opencode/skills/dk-lore): chunks, index, glossary and links agree
if command -v python3 >/dev/null; then
	python3 .opencode/skills/dk-lore/scripts/check.py >/dev/null || {
		python3 .opencode/skills/dk-lore/scripts/check.py >&2 || true; exit 1; }
fi
echo "lint: ok"
