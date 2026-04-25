#!/usr/bin/env bash
# .autopilot/hooks/commit-msg-protect.sh — trailer-dependent enforcement.
#
# Runs AFTER pre-commit, at commit-msg time, where $1 is the authoritative
# commit message file. This is the only hook phase where `git commit -m ...`
# reliably exposes the new message to inspection.
#
# Enforces:
#   1. New IMMUTABLE blocks require 'IMMUTABLE-ADD: <name>' trailer.
#   2. Commits with >5 deletes OR any delete under Assets/Scripts|Tests|Prefabs
#      or Document/ require 'cleanup-operator-approved: yes' trailer.

set -euo pipefail

msg_file="${1:-}"
if [ -z "$msg_file" ] || [ ! -f "$msg_file" ]; then
  echo "commit-msg-protect: expected commit message file as \$1"
  exit 1
fi
commit_msg=$(cat "$msg_file")

PROMPT=".autopilot/PROMPT.md"

has_trailer() {
  local key="$1" expected="$2"
  local line
  line=$(printf '%s\n' "$commit_msg" | grep -Ei "^${key}:[[:space:]]*" | head -1 || true)
  [ -z "$line" ] && return 1
  local val
  val=$(printf '%s' "$line" | sed -E "s/^${key}:[[:space:]]*//I")
  if [ "$expected" = "*" ]; then
    [ -n "$val" ]
  else
    [ "${val,,}" = "${expected,,}" ]
  fi
}

# ---------------------------------------------------------------------------
# Bulk-delete / sensitive-path trailer gate.
# ---------------------------------------------------------------------------
deleted_files=$(git diff --cached --name-only --diff-filter=D)
deleted_count=$(printf '%s' "$deleted_files" | grep -c . || true)

if [ "$deleted_count" -gt 5 ]; then
  if ! has_trailer "cleanup-operator-approved" "yes"; then
    echo "commit-msg-protect: commit deletes $deleted_count files (>5)."
    echo "  Requires 'cleanup-operator-approved: yes' trailer."
    exit 1
  fi
fi

if [ -n "$deleted_files" ]; then
  # Round-3 F15: sensitive deletion paths used to be hardcoded as
  # `Assets/Scripts|Tests|Prefabs|Document/`, leaking the Unity card-game
  # source project's tree into every template-applied repo. Now read from
  # `config.json.sensitive_delete_paths` (an array of path prefixes); fall
  # back to a sensible engine-agnostic default.
  cfg_path=".autopilot/config.json"
  sensitive_paths=""
  if [ -f "$cfg_path" ]; then
    if command -v jq >/dev/null 2>&1; then
      sensitive_paths=$(jq -r '.sensitive_delete_paths // [] | join("|")' "$cfg_path" 2>/dev/null || true)
    else
      # jq-less fallback — naive single-line extractor for an array of strings.
      sensitive_paths=$(python3 - "$cfg_path" <<'PY' 2>/dev/null || true
import json, sys
try:
    cfg = json.load(open(sys.argv[1], encoding='utf-8'))
    print('|'.join(cfg.get('sensitive_delete_paths') or []))
except Exception:
    pass
PY
)
    fi
  fi
  # Default if config is missing the key. Keep `Document/` because every
  # DAD-using project has a Document/dialogue/ tree that should not be
  # silently deleted.
  if [ -z "$sensitive_paths" ]; then
    sensitive_paths="Document/"
  fi
  # Build a regex like `^(Document/|src/|Assets/Scripts/)`.
  sensitive_regex="^(${sensitive_paths})"
  sensitive=$(printf '%s\n' "$deleted_files" | grep -E "$sensitive_regex" || true)
  if [ -n "$sensitive" ] && ! has_trailer "cleanup-operator-approved" "yes"; then
    echo "commit-msg-protect: commit deletes file(s) under sensitive paths (${sensitive_paths}):"
    printf '  %s\n' $sensitive
    echo "  Requires 'cleanup-operator-approved: yes' trailer."
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# New-IMMUTABLE-marker authorization.
# ---------------------------------------------------------------------------
if ! git diff --cached --name-only | grep -qx "$PROMPT"; then
  exit 0
fi
if ! git rev-parse --verify HEAD >/dev/null 2>&1; then
  exit 0
fi

# Round-3 F19: skip the IMMUTABLE-ADD authorization gate when PROMPT.md is
# being newly added rather than modified. This check exists to prevent self-
# evolution from silently granting itself new charter blocks; on the first
# `chore: apply autopilot-dad-template` commit, PROMPT.md doesn't exist in
# HEAD so every IMMUTABLE marker would be flagged as "newly introduced" and
# the operator would have to write IMMUTABLE-ADD trailers for every block.
# That's not the gate's intent.
if git diff --cached --name-only --diff-filter=A | grep -qx "$PROMPT"; then
  exit 0
fi

# Round-3 F19: this regex used to be `\[IMMUTABLE:BEGIN [a-z-]+\]` (square-
# bracket form) but PROMPT.md actually uses HTML-comment markers
# `<!-- IMMUTABLE:<name>:BEGIN -->`. Result: grep -oE found nothing on every
# commit that touched PROMPT.md, and because line 2 had no `|| true`, the
# empty grep + pipefail propagated `set -e` and **silently aborted every
# such commit with exit 1 and no diagnostic**. The bug went undetected for
# ages because the F18-pre `.githooks/commit-msg` shim didn't exist, so
# commit-msg-protect.sh was never invoked. Fix: match the real syntax and
# add `|| true` to the second pipeline so a no-marker file is treated as
# "no markers" rather than as a script failure.
base_markers=$(git show "HEAD:$PROMPT" 2>/dev/null | grep -oE '<!--[[:space:]]*IMMUTABLE:[a-z-]+:BEGIN[[:space:]]*-->' | sort -u || true)
head_markers=$(git show ":$PROMPT" 2>/dev/null | grep -oE '<!--[[:space:]]*IMMUTABLE:[a-z-]+:BEGIN[[:space:]]*-->' | sort -u || true)
added_markers=$(comm -23 <(printf '%s\n' "$head_markers") <(printf '%s\n' "$base_markers") \
                  | sed -E 's/^<!--[[:space:]]*IMMUTABLE:([a-z-]+):BEGIN[[:space:]]*-->$/\1/' | grep -v '^$' || true)

for name in $added_markers; do
  if ! printf '%s\n' "$commit_msg" | grep -qE "^IMMUTABLE-ADD:[[:space:]]*${name}[[:space:]]*$"; then
    echo "commit-msg-protect: new IMMUTABLE block '$name' introduced without authorization."
    echo "  Commit message must include on its own line: 'IMMUTABLE-ADD: $name'"
    echo "  This prevents self-evolution from granting itself new charter."
    exit 1
  fi
done

exit 0
