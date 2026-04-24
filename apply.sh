#!/usr/bin/env bash
# apply.sh — autopilot-dad-template installer (Unix).
# Run from the TARGET project root:
#   curl -fsSL https://raw.githubusercontent.com/mizan0515/autopilot-dad-template/main/apply.sh | bash
# or clone this repo and run ./apply.sh from target root.

set -euo pipefail

TEMPLATE_URL="${AUTOPILOT_TEMPLATE_URL:-https://github.com/mizan0515/autopilot-dad-template.git}"
TARGET="$(pwd)"
CONFLICTS="$TARGET/.apply-conflicts"

if [ ! -d "$TARGET/.git" ]; then
  echo "[apply] error: $TARGET is not a git repo. Run 'git init' first." >&2
  exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "[apply] fetching template from $TEMPLATE_URL"
git clone --depth 1 "$TEMPLATE_URL" "$WORK/template" >/dev/null

mkdir -p "$CONFLICTS"
conflict_count=0

copy_if_missing() {
  local rel="$1"
  local src="$WORK/template/$rel"
  local dst="$TARGET/$rel"
  if [ ! -e "$src" ]; then return; fi
  if [ -e "$dst" ]; then
    if ! diff -q "$src" "$dst" >/dev/null 2>&1; then
      mkdir -p "$(dirname "$CONFLICTS/$rel")"
      cp "$src" "$CONFLICTS/$rel"
      conflict_count=$((conflict_count + 1))
      echo "[apply] conflict: $rel (saved to .apply-conflicts/)"
    fi
  else
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    echo "[apply] installed: $rel"
  fi
}

# Walk template files (exclude .git, apply.*, README.md)
cd "$WORK/template"
while IFS= read -r -d '' f; do
  rel="${f#./}"
  case "$rel" in
    .git/*|apply.sh|apply.ps1|README.md|LICENSE) continue ;;
  esac
  cd "$TARGET" && copy_if_missing "$rel"
  cd "$WORK/template"
done < <(find . -type f -print0)

cd "$TARGET"

# Remove empty conflicts dir
if [ "$conflict_count" -eq 0 ]; then
  rmdir "$CONFLICTS" 2>/dev/null || true
fi

# Register hooks
if [ -d .autopilot/hooks ]; then
  chmod +x .autopilot/hooks/*.sh .autopilot/hooks/pre-commit 2>/dev/null || true
  git config core.hooksPath .autopilot/hooks
  echo "[apply] hooks registered (core.hooksPath=.autopilot/hooks)"
fi

echo ""
if [ "$conflict_count" -gt 0 ]; then
  echo "[apply] done with $conflict_count conflict(s). Review .apply-conflicts/ and merge manually."
  if [ "$conflict_count" -ge 5 ]; then
    echo "[apply] WARNING: 5+ conflicts — stopping automatic apply. Report to operator." >&2
    exit 2
  fi
else
  echo "[apply] done. No conflicts."
fi

cat <<'HINT'

Next steps:
  1. Edit .autopilot/PROMPT.md — replace <<PROJECT_NAME>>, <<PROJECT_DESCRIPTION>>, <<PRODUCT_DIRECTIVE>>
  2. Edit .autopilot/BACKLOG.md — replace seed tasks with real first items
  3. Commit: git add .autopilot && git commit -m "chore: apply autopilot-dad-template"
  4. Run first iter: paste .autopilot/RUN.claude-code.md into Claude Code desktop
HINT
