#!/usr/bin/env bash
# base/tools/write-utf8-nobom.sh — peer of Write-Utf8NoBom.ps1.
#
# Write text to a path as UTF-8 without a BOM. macOS / Linux shells already
# default to UTF-8-no-BOM, so this wrapper mostly exists so cross-platform
# runners can call the same invocation from both sides.
#
# Usage:
#   bash base/tools/write-utf8-nobom.sh <path> "<text>"          # overwrite
#   bash base/tools/write-utf8-nobom.sh --append <path> "<text>" # append

set -uo pipefail

append=0
if [ "${1:-}" = "--append" ]; then
  append=1
  shift
fi

path="${1:-}"
text="${2:-}"

if [ -z "$path" ]; then
  echo "usage: write-utf8-nobom.sh [--append] <path> <text>" >&2
  exit 2
fi

dir="$(dirname "$path")"
mkdir -p "$dir" 2>/dev/null || true

# Strip any stray BOM from the input and write as UTF-8.
cleaned="$(printf '%s' "$text" | LC_ALL=C sed -e $'s/^\xEF\xBB\xBF//')"

if [ "$append" -eq 1 ]; then
  printf '%s' "$cleaned" >> "$path"
else
  printf '%s' "$cleaned" > "$path"
fi
