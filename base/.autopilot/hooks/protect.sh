#!/usr/bin/env bash
# .autopilot/hooks/protect.sh — pre-commit guard for the autopilot's safety surface.
#
# Enforces (pre-commit, no access to the new commit message):
#   1. PROMPT.md IMMUTABLE blocks cannot be modified.
#   2. Removed IMMUTABLE markers are rejected outright.
#   3. .autopilot/MVP-GATES.md must exist and carry a parseable "Gate count:"
#      line — the halt trigger depends on it.
#   4. .autopilot/STATE.md must keep a minimum set of entries under
#      `protected_paths:` (the self-protection list the loop must not strip).
#   5. Hard-cap: >20 file deletions per commit is always rejected.
#
# Trailer-dependent enforcement (new-IMMUTABLE-marker authorization,
# cleanup-operator-approved for >5 or sensitive deletes) runs in commit-msg.sh,
# because the pre-commit hook has no reliable read of the pending message
# (`git commit -m ...` does not populate .git/COMMIT_EDITMSG before pre-commit).
#
# Install via `.autopilot/project.ps1 install-hooks` or `project.sh install-hooks`.

set -euo pipefail

PROMPT=".autopilot/PROMPT.md"
MVPGATES=".autopilot/MVP-GATES.md"
STATE=".autopilot/STATE.md"

# ---------------------------------------------------------------------------
# Check 5: hard-cap on bulk deletes (>5 and sensitive-path checks run in
# commit-msg because they need access to the commit message trailers).
# ---------------------------------------------------------------------------
deleted_count=$(git diff --cached --name-only --diff-filter=D | grep -c . || true)

if [ "$deleted_count" -gt 20 ]; then
  echo "protect.sh: commit deletes $deleted_count files; hard cap is 20 per commit."
  echo "  → reject. Split into multiple cleanup PRs."
  exit 1
fi

# ---------------------------------------------------------------------------
# Check 3 + 4: sentinel files must stay healthy on every commit.
# ---------------------------------------------------------------------------
if [ ! -f "$MVPGATES" ]; then
  echo "protect.sh: $MVPGATES missing. This file is the MVP halt trigger;"
  echo "  losing it disables a safety path. Restore before committing."
  exit 1
fi

if ! grep -qE '^Gate count:[[:space:]]*[0-9]+' "$MVPGATES"; then
  echo "protect.sh: $MVPGATES is missing a parseable 'Gate count: <N>' line."
  echo "  The halt trigger depends on it. Restore."
  exit 1
fi

if [ ! -f "$STATE" ]; then
  echo "protect.sh: $STATE missing. Cannot verify protected_paths."
  exit 1
fi

# These paths must remain in STATE.md protected_paths: at all times — they
# are the loop's self-protection list. Removing any of them weakens the
# auto-merge refusal gate.
REQUIRED_PROTECTED=(
  ".autopilot/PROMPT.md"
  ".autopilot/hooks/"
  ".autopilot/project.ps1"
  ".autopilot/project.sh"
  "Packages/manifest.json"
  "ProjectSettings/"
  "PROJECT-RULES.md"
  "CLAUDE.md"
  "AGENTS.md"
  "Document/dialogue/"
)
for p in "${REQUIRED_PROTECTED[@]}"; do
  if ! grep -qE "^[[:space:]]*-[[:space:]]*${p//\//\\/}[[:space:]]*$" "$STATE"; then
    echo "protect.sh: STATE.md protected_paths is missing required entry: '$p'"
    echo "  → reject. Restore it before committing."
    exit 1
  fi
done

# ---------------------------------------------------------------------------
# Checks 1 + 2: PROMPT.md IMMUTABLE integrity.
# ---------------------------------------------------------------------------
if ! git diff --cached --name-only | grep -qx "$PROMPT"; then
  # PROMPT.md not being committed — no block check needed.
  exit 0
fi

# First-ever commit (no HEAD). Scaffolding pass.
if ! git rev-parse --verify HEAD >/dev/null 2>&1; then
  exit 0
fi

BLOCKS=(product-directive core-contract boot budget blast-radius halt cleanup-safety mvp-gate exit-contract)

tmp_base=$(mktemp); tmp_head=$(mktemp)
trap 'rm -f "$tmp_base" "$tmp_head"' EXIT

git show "HEAD:$PROMPT" > "$tmp_base" 2>/dev/null || { echo "protect.sh: cannot read HEAD:$PROMPT"; exit 1; }
git show ":$PROMPT"     > "$tmp_head"

# Detect removed markers (old IMMUTABLE block deleted). Never allowed.
# (New-marker authorization via IMMUTABLE-ADD trailer is enforced in commit-msg.sh.)
new_markers=$(grep -oE '\[IMMUTABLE:BEGIN [a-z-]+\]' "$tmp_head" | sort -u)
old_markers=$(grep -oE '\[IMMUTABLE:BEGIN [a-z-]+\]' "$tmp_base" | sort -u)
removed_markers=$(comm -13 <(printf '%s\n' "$new_markers") <(printf '%s\n' "$old_markers") | sed -E 's/^\[IMMUTABLE:BEGIN ([a-z-]+)\]$/\1/')
if [ -n "$removed_markers" ]; then
  echo "protect.sh: IMMUTABLE block(s) removed from $PROMPT:"
  printf '  %s\n' $removed_markers
  echo "  → reject. IMMUTABLE blocks are append-only and content-locked."
  exit 1
fi

# Check 1: for each of the named BLOCKS that exist in HEAD, content must
# match in the staged version (block deletion/modification blocked).
for name in "${BLOCKS[@]}"; do
  begin="\[IMMUTABLE:BEGIN $name\]"
  end="\[IMMUTABLE:END $name\]"

  # Markers must still exist in the new version.
  if ! grep -q "$begin" "$tmp_head" || ! grep -q "$end" "$tmp_head"; then
    echo "protect.sh: IMMUTABLE markers for '$name' are missing from $PROMPT"
    echo "  → reject. Restore [IMMUTABLE:BEGIN $name] ... [IMMUTABLE:END $name]."
    exit 1
  fi

  base_block=$(awk "/$begin/,/$end/" "$tmp_base")
  head_block=$(awk "/$begin/,/$end/" "$tmp_head")

  # Bootstrap: block doesn't exist in HEAD but was just added. Allowed here
  # (the commit-msg hook enforces the IMMUTABLE-ADD trailer requirement).
  if [ -z "$base_block" ]; then
    continue
  fi

  if [ "$base_block" != "$head_block" ]; then
    echo "protect.sh: IMMUTABLE block '$name' was modified in $PROMPT"
    echo "  → reject. These blocks are self-evolution-immutable."
    echo "  → if you genuinely need to change one, do it in a separate operator"
    echo "    commit with the block content restored and the change in a"
    echo "    dedicated mutable section instead."
    exit 1
  fi
done

exit 0
